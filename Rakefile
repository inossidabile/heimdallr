require "bundler/gem_tasks"

Dir.chdir File.dirname(__FILE__)

gemspec = Bundler.load_gemspec Dir["{,*}.gemspec"].first

task :release => :prepare_for_release

task :prepare_for_release do
  readme = File.read('README.yard.md')
  readme.gsub! /{([[:alnum:]:]+)}/i do |match|
    %Q|[#{$1}](http://rubydoc.info/gems/#{gemspec.name}/#{gemspec.version}/#{$1.gsub '::', '/'})|
  end

  File.open('README.md', 'w') do |f|
    f.write readme
  end

  %x|git add README.md|
  #%x|git commit -m "Bump version to #{gemspec.version}."|
end