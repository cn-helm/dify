require 'base64'
require 'json'
require 'open3'
require 'tempfile'
require 'yaml'

CHART = File.expand_path('..', __dir__)
CATALOG = YAML.load_file(File.join(CHART, 'files/vector-backends.yaml'))

def assert(condition, message)
  raise message unless condition
end

def render(overrides = {}, credentials: true, valid: true, **settings)
  overrides = overrides.merge(settings)
  values = credentials ? { 'security' => { 'existingSecret' => 'test-credentials' } } : {}
  values.merge!(overrides)
  Tempfile.create(['dify-values', '.yaml']) do |file|
    file.write(YAML.dump(values))
    file.flush
    output, error, status = Open3.capture3('helm', 'template', 'test', CHART, '-f', file.path)
    unless valid
      assert(!status.success?, "Invalid configuration was accepted: #{overrides.keys}")
      return []
    end
    assert(status.success?, "Helm render failed: #{error}")
    documents = YAML.load_stream(output).compact
    identities = documents.map { |entry| [entry['kind'], entry.dig('metadata', 'name')] }
    assert(identities.uniq.length == identities.length, 'Duplicate Kubernetes object identity')
    documents.each do |entry|
      pod = entry.dig('spec', 'template', 'spec')
      next unless pod
      (pod.fetch('containers', []) + pod.fetch('initContainers', [])).each do |container|
        names = container.fetch('env', []).map { |variable| variable.fetch('name') }
        assert(names.uniq.length == names.length, "Duplicate env in #{container['name']}")
      end
    end
    if ENV['KUBECONFORM']
      _result, failure, checked = Open3.capture3(
        ENV.fetch('KUBECONFORM'), '-strict', '-kubernetes-version',
        ENV.fetch('KUBERNETES_VERSION', '1.31.0'), '-cache', ENV.fetch('SCHEMA_CACHE', '/tmp/dify-schema-cache'),
        stdin_data: output
      )
      assert(checked.success?, "Kubernetes schema validation failed: #{failure} #{_result}")
    end
    documents
  end
end

def find(documents, kind, suffix)
  documents.find { |entry| entry['kind'] == kind && entry.dig('metadata', 'name').end_with?(suffix) } ||
    raise("Missing #{kind} #{suffix}")
end

baseline = render
core = find(baseline, 'Deployment', '-core').dig('spec', 'template', 'spec')
assert(core['containers'].map { |container| container['name'] }.sort == %w[api beat websocket worker], 'Missing core roles')
ports = core['containers'].flat_map { |container| container.fetch('ports', []).map { |port| port['containerPort'] } }
assert(ports.uniq == ports, 'Colliding core container ports')
assert(core['automountServiceAccountToken'] == false, 'Service account token exposed to runtime containers')
core['containers'].each do |container|
  assert(!container.fetch('volumeMounts', []).any? { |mount| mount['name'] == 'api-access' }, 'Runtime token mount')
end
%w[sandbox local-sandbox].each do |component|
  kind = component == 'sandbox' ? 'Deployment' : 'StatefulSet'
  container = find(baseline, kind, "-#{component}").dig('spec', 'template', 'spec', 'containers', 0)
  assert(container.fetch('envFrom', []).empty?, 'Sandbox inherited broad credentials')
  names = container.fetch('env').map { |variable| variable['name'] }
  assert(!names.include?('DB_PASSWORD'), 'Sandbox received database password')
end

generated = render({}, credentials: false)
secret = find(generated, 'Secret', '-secrets').fetch('data')
secret.each { |key, value| assert(!Base64.strict_decode64(value).empty?, "Empty #{key}") }
jwe = Base64.strict_decode64(secret.fetch('DIFY_AGENT_SERVER_SECRET_KEY'))
assert(jwe.match?(/\A[A-Za-z0-9_-]{43}\z/) && Base64.urlsafe_decode64(jwe).bytesize == 32, 'Invalid JWE key')
assert(render == baseline, 'Existing-Secret rendering is nondeterministic')

split = render('core' => { 'mode' => 'split' }, 'persistence' => { 'accessMode' => 'ReadWriteMany' })
%w[api websocket worker beat].each { |role| find(split, 'Deployment', "-#{role}") }
render({ 'core' => { 'mode' => 'split' } }, valid: false)
render({ 'agent' => { 'enabled' => 'not-a-boolean' } }, valid: false)
render({ 'exposure' => { 'type' => 'Ingress' } }, valid: false)
render({ 'extraEnv' => { 'DB_PASSWORD' => 'invalid' } }, valid: false)
render({ 'database' => { 'name' => "bad';DROP" } }, valid: false)
render({ 'database' => { 'mode' => 'external', 'host' => 'db' } }, credentials: false, valid: false)
render({ 'agent' => { 'runtime' => 'e2b' } }, valid: false)
render({ 'vectorStore' => { 'mode' => 'external' } }, valid: false)
override = render('extraEnv' => { 'LOG_LEVEL' => 'DEBUG' })
assert(find(override, 'ConfigMap', '-config').dig('data', 'LOG_LEVEL') == 'DEBUG', 'Config override failed')

mysql = render('database' => { 'type' => 'mysql' })
mysql_config = find(mysql, 'ConfigMap', '-config').fetch('data')
assert(mysql_config['DB_PORT'] == '3306' && mysql_config['DB_USERNAME'] == 'root', 'MySQL inference failed')
find(mysql, 'StatefulSet', '-mysql')
assert(!mysql.any? { |entry| entry.dig('metadata', 'name').end_with?('-postgres') }, 'Unexpected PostgreSQL')

reduced = render('agent' => { 'enabled' => false }, 'collaboration' => { 'enabled' => false })
assert(!reduced.any? { |entry| entry.dig('metadata', 'name').match?(/-(local-sandbox|agent|agent-proxy|websocket)$/) }, 'Disabled feature leaked resources')
assert(!find(reduced, 'ConfigMap', '-nginx').dig('data', 'default.conf').include?('-websocket'), 'Disabled websocket upstream')

CATALOG.each do |type, backend|
  if backend['bundled']
    documents = render('vectorStore' => { 'type' => type })
    assert(find(documents, 'ConfigMap', '-config').dig('data', 'VECTOR_STORE') == type, 'Wrong vector type')
    if type != 'weaviate'
      find(documents, 'StatefulSet', "-vector-#{type}")
      api = find(documents, 'Deployment', '-core').dig('spec', 'template', 'spec', 'containers', 0)
      assert(api['env'].any? { |entry| entry.dig('valueFrom', 'secretKeyRef', 'key') == 'VECTOR_STORE_PASSWORD' }, 'Missing vector credentials')
    end
  else
    render({ 'vectorStore' => { 'type' => type } }, valid: false)
  end
  config = backend.fetch('required').to_h { |key| [key, key.end_with?('_PORT') ? '5432' : 'external.example.com'] }
  external = render('vectorStore' => {
    'type' => type, 'mode' => 'external', 'endpoint' => 'http://weaviate.example.com:8080',
    'grpcEndpoint' => 'grpc://weaviate.example.com:50051', 'config' => config,
    'existingSecret' => 'vector-credentials'
  })
  assert(!external.any? { |entry| entry['kind'] == 'StatefulSet' && entry.dig('metadata', 'name').match?(/-(vector-.+|weaviate)$/) }, 'External backend deployed locally')
end

%w[ingress external split].each do |example|
  render(YAML.load_file(File.join(CHART, "ci/#{example}.yaml")))
end
runtime = render('agent' => {
  'runtime' => 'e2b', 'existingSecret' => 'e2b-credentials', 'config' => {
    'DIFY_AGENT_STUB_API_BASE_URL' => 'https://agent.example.com/agent-stub',
    'DIFY_AGENT_SANDBOX_FILES_BASE_URL' => 'https://dify.example.com'
  }
})
assert(!runtime.any? { |entry| entry.dig('metadata', 'name').end_with?('-local-sandbox') }, 'External runtime deployed local sandbox')
assert(find(runtime, 'ConfigMap', '-nginx').dig('data', 'default.conf').include?('location /agent-stub/'), 'External runtime has no stub route')

values = YAML.load_file(File.join(CHART, 'values.yaml'))
questions = YAML.load_file(File.join(CHART, 'questions.yaml')).fetch('questions').dup
question_count = 0
until questions.empty?
  question = questions.shift
  value = question.fetch('variable').split('.').reduce(values) { |current, key| current.fetch(key) }
  assert(!question['options'] || question['options'].include?(value), "Invalid enum #{question['variable']}")
  assert(!question['min'] || value >= question['min'], "Invalid minimum #{question['variable']}")
  questions.concat(question.fetch('subquestions', []))
  question_count += 1
end
puts "PASS: default, split, MySQL, #{CATALOG.length} vector types, external services, credentials, feature flags, invalid inputs, #{question_count} Rancher fields"