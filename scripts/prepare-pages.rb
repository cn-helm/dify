require 'fileutils'
require 'yaml'

root = File.expand_path('..', __dir__)
destination = File.expand_path(ARGV.fetch(0, 'site'))
FileUtils.mkdir_p(destination)

configuration = {
  'title' => 'Dify Helm Chart',
  'description' => 'Helm repository and deployment documentation for Dify',
  'theme' => 'jekyll-theme-minimal',
  'url' => ENV.fetch('PAGES_ORIGIN', ''),
  'baseurl' => ENV.fetch('PAGES_BASE_PATH', '')
}
File.write(File.join(destination, '_config.yml'), YAML.dump(configuration))

{ 'README.md' => 'index.md', 'COMPATIBILITY.md' => 'COMPATIBILITY.md' }.each do |source, target|
  metadata = YAML.dump('layout' => 'default', 'title' => configuration.fetch('title'))
  markdown = File.read(File.join(root, source))
  File.write(File.join(destination, target), "#{metadata}---\n\n#{markdown}")
end

%w[ci files].each do |directory|
  FileUtils.cp_r(File.join(root, directory), destination)
end