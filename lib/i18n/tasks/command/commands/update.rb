# frozen_string_literal: true
require 'pry'

module I18n::Tasks
  module Command
    module Commands
      module Update
        include Command::Collection
        cmd :update,
            pos:  '[locales key value]',
            desc: "Creates or replaces an existing key if it exists in the locales files"

        cmd :remove,
            pos: '[key...]'
            desc: 'removes key'

        def log(str)
          puts "[ I18n-tasks ] #{str}"
        end

        def update_backups(force_backup = false)
          log("Updating backups") if force_backup
          system("mkdir i18n_backups") if !File.exist?("i18n_backups")
          i18n.locales.each { |locale|
            i18n.data.config[:read].each { |path|
              path = path.gsub("%{locale}", locale)
              dir = path.split("/")
              dir = dir.first(dir.size - 1).join("/")
              backup_dir = dir.gsub("config/locales", "i18n_backups")
              system("mkdir #{backup_dir}") if !File.exist?(backup_dir)
              backup_path = path.gsub("config/locales", "i18n_backups")
              system("cp #{path} #{backup_path}") if force_backup || !File.exist?("#{backup_path}")
            }
          }
        end

        def get_forests
          log("Retrieving current forest...")
          @current_forest = i18n.data_forest
          log("Retrieving backup forest...")
          @backup_forest = I18n::Tasks::BaseTask.new({
            data: {
              read: i18n.data.config[:read].map { |p| p.gsub("config/locales", "i18n_backups") },
              write: i18n.data.config[:write].map { |p| p.gsub("config/locales", "i18n_backups") },
            }
          }).data_forest
        end

        def get_keys_from_forest(type, node)
          if node.children.nil?
            @keys[type][node.full_key] = node.value
          else
            node.children.each { |subnode|
              get_keys_from_forest(type, subnode)
            }
          end
        end

        def check_differences
          @differing = []
          @removed = []
          @added = []
          @keys[:current].each { |k, v|
            cleaned = k.split(".")
            cleaned.shift
            @differing.push(cleaned.join(".")) if !@keys[:backup][k].nil? && @keys[:backup][k] != v
          }
          @keys[:backup].each { |k, v|
            cleaned = k.split(".")
            cleaned.shift
            @removed.push(cleaned.join(".")) if @keys[:current][k].nil?
          }
          @keys[:current].each { |k, v|
            cleaned = k.split(".")
            cleaned.shift
            @added.push(cleaned.join(".")) if @keys[:backup][k].nil?
          }
        end

        def get_differing_keys
          @keys = {
            current: {},
            backup: {}
          }
          get_keys_from_forest(:current, @current_forest.get(@base_locale))
          get_keys_from_forest(:backup, @backup_forest.get(@base_locale))
          check_differences
        end

        def process_differing_keys
          @locales = i18n.locales

          log("Found #{@differing.count} differing keys:")
          @differing.each { |k|
            log("  - #{k}")
          }
          log("Found #{@added.count} added keys:")
          @added.each { |k|
            log("  - #{k}")
          }
          log("Found #{@removed.count} removed keys:")
          @removed.each { |k|
            log("  - #{k}")
          }
          puts ""
          i = 0
          log("Translation disabled, will set differing / removed keys to #{@base_locale}") if !@translate
          @locales.each { |locale|
            i += 1
            something_changed = false
            log("#{locale} (#{i} / #{@locales.count}):")
            if @differing.count > 0
              log("  Removing differing keys...")
                @differing.each { |k|
                @current_forest.mv_key!(compile_key_pattern("#{locale}.#{k}"), '', root: true)
                something_changed = true
              }
            end
            if @removed.count > 0
              log("  Removing removed keys...")
              @removed.each { |k|
                @current_forest.mv_key!(compile_key_pattern("#{locale}.#{k}"), '', root: true)
                something_changed = true
              }
            end
            if something_changed
              log("  Rewriting locale...")
              i18n.data.set(locale, @current_forest.get(locale))
            end
          }
          if @translate
            log("Able to translate, retrieving differing forest (will take a little while")
            missing = i18n.missing_diff_forest i18n.locales, @base_locale
            log("Adding and translating added keys...")
            translated = i18n.translate_forest missing, from: @base_locale, backend: :google
            @current_forest.merge! translated
          else
            binding.pry
            # log("Setting every differing / removed key to #{@base_locale}...")
            # data = {}
            # @differing.each { |k|
            #   k = "en.#{k}"

            # }

            # @locales.each { |locale|
            #   @differing.each { |k|
            #     k = "#{locale}.#{k}"
            #     node = I18n::Tasks::Data::Tree::Node.new(key: k, value: )
            #   }
            #   @current_forest.set()
            # }
          end
        end

        def parse_arguments(opt)
          @translate = true
          @base_locale = "en"
          opt.each { |arg|
            split = arg.split("=")
            instance_variable_set("@#{split.first}", split.second == "true" || split.second == "false" ? split.second == "true" : split.second)
          }
        end

        def update(opt = {})
          parse_arguments(opt[:arguments])
          update_backups(false)
          get_forests
          get_differing_keys
          return if @differing.count == 0 && @added.count == 0 && @removed.count == 0
          process_differing_keys

          log("Writing everything back to the files (this will take a while)...")
          i18n.data.write @current_forest
          update_backups(true)
          log("Running js export (will also take a while)...")
          system("rake i18n:js:export")
        end
      end
    end
  end
end
