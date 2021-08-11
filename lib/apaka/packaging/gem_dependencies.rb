require 'autoproj'
require 'bundler'
require 'digest/md5'
require 'json'
require 'open3'
require 'apaka/packaging/packager'

module Apaka
    module Packaging
        class GemDependencies
            @@known_gems = {}
            @@gemfile_to_specs = {}
            @@gemfile_md5 = {}


            # Path to autoproj default gemfile
            #
            def self.gemfile
                File.join(Autoproj.root_dir,"install","gems","Gemfile")
            end

            # Collect all gem specification that are defined through a given
            # Gemfile
            # @param gemfile [String] Path to autoproj default gemfile
            def self.all_gem_specs(gemfile = GemDependencies.gemfile)
                unless File.exist?(gemfile)
                    raise "Apaka::Packaging::Autoproj2Adapter.all_required_gems " \
                        "Gemfile #{gemfile} does not exist"
                end
                GemDependencies.get_gem_specs(gemfile)
            end

            def self.get_md5(file)
                Digest::MD5.digest(File.read(file))
            end

            # Retrieve the gem specs via bundler for a given Gemfile
            # @param gemfile [String] Path to the Bundler Gemfile to resolve
            def self.get_gem_specs(gemfile)
                if @@gemfile_md5.has_key?(gemfile)
                    md5 = @@gemfile_md5[gemfile]
                    if md5 == GemDependencies.get_md5(gemfile)
                        return @@gemfile_to_specs[gemfile]
                    end
                end

                gems_definitions = Bundler::Definition.build(gemfile, nil,nil)
                gem_specs = gems_definitions.resolve_remotely!

                gems = {}
                gem_specs.each do |spec|
                    gems[spec.name] = spec
                end

                @@gemfile_to_specs[gemfile] = gems
                @@gemfile_md5[gemfile] = GemDependencies.get_md5(gemfile)

                gems
            end

            def self.prepare_gemfile(gemfile= "/tmp/apaka/Gemfile")
                tmp_dir = File.dirname(gemfile)
                FileUtils.mkdir_p tmp_dir unless File.directory?(tmp_dir)
                FileUtils.cp GemDependencies.gemfile, gemfile
            end

            def self.prepare_new_gemfile(gemfile= "/tmp/apaka/Gemfile")
                tmp_dir = File.dirname(gemfile)
                FileUtils.mkdir_p tmp_dir unless File.directory?(tmp_dir)
                File.open(gemfile,"w") do |file|
                    file.puts "source 'https://rubygems.org'"
                end
                gemfile
            end

            # Resolve all dependencies of a list of name or |name,version| tuples of gems
            # @returns List of dependency names
            def self.resolve_all(gems = [], gemfile: "/tmp/apaka/Gemfile.all")
                GemDependencies.prepare_gemfile(gemfile)
                File.open(gemfile,"a") do |f|
                    f.puts "group :extra do"
                    gems.each do |gem|
                        if gem.kind_of?(Array)
                            name,version = gem
                        else
                            name = gem
                        end

                        if version
                            if version =~ /^[0-9].*/
                                f.puts "    gem \"#{name}\", \"== #{version}\""
                            else
                                f.puts "    gem \"#{name}\", \"#{version}\""
                            end
                        else
                            f.puts "    gem \"#{name}\", \">= 0\""
                        end
                    end
                    f.puts "end"
                end

                specs = GemDependencies.get_gem_specs(gemfile)
                return specs.keys if gems.empty?

                deps = Set.new
                gems.each do |gem_name, gem_version|
                    specs[gem_name].dependencies.each do |d|
                        if d.type == :runtime
                            deps << d.name
                        end
                    end
                end
                deps.to_a
            end

            # Resolve the dependency of a gem using `gem dependency <gem_name>`
            # This will only work if the local installation is update to date
            # regarding the gems
            # return {:deps => , :version =>  }
            def self.resolve_by_name(gem_name, version: nil, gemfile: "/tmp/apaka/Gemfile.#{gem_name}")
                unless gem_name.kind_of?(String)
                    raise "Apaka::Packaging::GemDependencies.resolve_by_name " \
                        "takes only gem name as argument, but got #{gem_name}"
                end

                unless version
                    GemDependencies.prepare_gemfile(gemfile)
                else
                    GemDependencies.prepare_new_gemfile(gemfile)
                end
                File.open(gemfile,"a") do |f|
                    f.puts "group :extra do"
                    if version 
                        f.puts "    gem \"#{gem_name}\", \"= #{version}\""
                    else
                        f.puts "    gem \"#{gem_name}\", \">= 0\""
                    end
                    f.puts "end"
                end
                specs = GemDependencies.get_gem_specs(gemfile)
                deps = []
                versions = []
                specs[gem_name].dependencies.each do |d|
                    if d.type == :runtime
                        deps << d.name
                        versions << d.requirement.to_s
                    end
                end
                {:deps => deps, :version => versions }
            end

            def self.is_gem?(gem_name)
                return @@known_gems[gem_name] if @@known_gems.has_key?(gem_name)

                gemfile = GemDependencies.prepare_new_gemfile("/tmp/apaka/Gemfile.is_gem.#{gem_name}")
                File.open(gemfile, "a") do |file|
                    file.puts "gem '#{gem_name}', \" >= 0 \""
                end

                begin
                    GemDependencies.resolve_by_name(gem_name, gemfile: gemfile)
                    result = true
                rescue Bundler::GemNotFound => e
                    result = false
                end
                @@known_gems[gem_name] = result
            end

            # Get the release date for a particular gem
            # if no version is given, then the latest is used
            #
            # This performs a webquery on rubygems.org
            def self.get_release_date(gem_name, version = nil)
                json_txt, err, status = Open3.capture3("curl https://rubygems.org/api/v1/versions/#{gem_name}.json")
                if status.success?
                    json = JSON.parse(json_txt)
                    json.each do |desc|
                        if not version or desc["number"] == version
                            built_at = desc['built_at']
                            Apaka::Packaging.info "GemDependencies: gem #{gem_name}, version #{version} built at: #{built_at}"
                            if built_at =~ /([0-9]{4}-[0-9]{2}-[0-9]{2})T/
                                return DateTime.strptime($1, "%Y-%m-%d")
                            end
                        end
                    end
                else
                    Apaka::Packaging.info "GemDependencies: gem #{gem_name}, version #{version} could not retrieve release date"
                end
                nil
            end
        end # GemDependencies
    end # Packaging
end # Apaka
