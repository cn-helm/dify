require 'date'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'yaml'

root = File.expand_path('..', __dir__)
workflow = YAML.load_file(File.join(root, '.github/workflows/chart.yaml'))
publish = workflow.fetch('jobs').fetch('publish')
raise 'Publishing must depend on validation' unless publish.fetch('needs') == 'validate'
raise 'Publishing must exclude pull requests' unless publish.fetch('if').include?("github.event_name != 'pull_request'")
raise 'Publishing must require the default branch' unless publish.fetch('if').include?('github.event.repository.default_branch')
%w[contents pages id-token].each do |permission|
  raise "Missing #{permission} write permission" unless publish.fetch('permissions').fetch(permission) == 'write'
end
steps = publish.fetch('steps')

def execute(*command, directory:, environment: {})
  output, error, status = Open3.capture3(environment, *command, chdir: directory)
  raise "#{command.first} failed: #{output} #{error}" unless status.success?
  output
end

Dir.mktmpdir('dify-pages-') do |temporary|
  site = File.join(temporary, 'site')
  execute('ruby', File.join(root, 'scripts/prepare-pages.rb'), site,
          directory: root, environment: { 'PAGES_ORIGIN' => 'https://example.github.io', 'PAGES_BASE_PATH' => '/dify' })
  configuration = YAML.load_file(File.join(site, '_config.yml'))
  raise 'Project site origin missing' unless configuration.fetch('url') == 'https://example.github.io'
  raise 'Project site path missing' unless configuration.fetch('baseurl') == '/dify'
  raise 'README content missing' unless File.read(File.join(site, 'index.md')).end_with?(File.read(File.join(root, 'README.md')))
  raise 'Examples missing' unless File.file?(File.join(site, 'ci/ingress.yaml'))

  steps.filter_map { |step| step['run'] }.each do |script|
    _output, error, status = Open3.capture3('bash', '-n', stdin_data: script)
    raise "Invalid workflow shell: #{error}" unless status.success?
  end
  restore = steps.find { |step| step['name'] == 'Restore previous Chart packages' }.fetch('run')
  index = steps.find { |step| step['name'] == 'Build Helm repository index' }.fetch('run')
  required_actions = %w[actions/configure-pages@v5 actions/upload-pages-artifact@v3 actions/deploy-pages@v4]
  required_actions.each do |action|
    raise "Missing #{action}" unless steps.any? { |step| step['uses'] == action }
  end

  %w[first existing].each do |scenario|
    directory = File.join(temporary, scenario)
    runner = File.join(directory, 'runner')
    FileUtils.mkdir_p([directory, runner, File.join(directory, 'dist')])
    execute('git', 'init', '--quiet', directory, directory: temporary)
    environment = { 'RUNNER_TEMP' => runner, 'PAGES_URL' => 'https://example.github.io/dify', 'CUSTOM_REPOSITORY_URL' => '' }
    if scenario == 'existing'
      previous = File.join(temporary, 'previous-chart')
      FileUtils.mkdir_p(previous)
      File.write(File.join(previous, 'Chart.yaml'), YAML.dump('apiVersion' => 'v2', 'name' => 'dify', 'version' => '0.0.9'))
      execute('helm', 'package', previous, '--destination', directory, directory: root)
      execute('helm', 'repo', 'index', directory, '--url', environment.fetch('PAGES_URL'), directory: root)
      execute('git', 'add', 'index.yaml', 'dify-0.0.9.tgz', directory: directory)
      execute('git', '-c', 'user.name=Chart Test', '-c', 'user.email=test@example.invalid',
              'commit', '--quiet', '-m', 'Fixture archive', directory: directory)
      execute('git', 'update-ref', 'refs/remotes/origin/gh-pages', 'HEAD', directory: directory)
    end
    execute('bash', '-c', restore, directory: directory, environment: environment)
    execute('helm', 'package', root, '--destination', File.join(directory, 'dist'), directory: root)
    FileUtils.cp([File.join(root, 'README.md'), File.join(root, 'COMPATIBILITY.md')], directory)
    execute('bash', '-c', index, directory: directory, environment: environment)
    published = YAML.safe_load(File.read(File.join(directory, 'dist/index.yaml')), permitted_classes: [Time, Date])
    entries = published.fetch('entries').fetch('dify')
    current_version = YAML.load_file(File.join(root, 'Chart.yaml')).fetch('version')
    expected_versions = scenario == 'existing' ? [current_version, '0.0.9'] : [current_version]
    raise 'Chart versions lost' unless (expected_versions - entries.map { |entry| entry.fetch('version') }).empty?
    entries.each do |entry|
      entry.fetch('urls').each do |url|
        raise 'Incorrect repository URL' unless url.start_with?('https://example.github.io/dify/')
        raise 'Historical archive missing' unless File.file?(File.join(directory, 'dist', File.basename(url)))
      end
    end
    raise 'Raw README missing' unless File.read(File.join(directory, 'dist/README.md')) == File.read(File.join(root, 'README.md'))
  end
end

puts 'PASS: Pages permissions, default-branch gate, README site paths, shell syntax, initial index and historical Chart preservation'