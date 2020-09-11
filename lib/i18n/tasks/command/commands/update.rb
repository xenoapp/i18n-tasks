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

        def update_log(str)
          puts "[ I18n-tasks ] #{str}"
        end

        def update_update_backups(force_backup = false)
          update_log("Updating backups") if force_backup
          system("mkdir i18n_backups") if !File.exist?("i18n_backups")
          ["base"].each { |locale|
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

        def update_get_forests
          update_log("Retrieving current forest...")
          @current_forest = i18n.data_forest
          update_log("Retrieving backup forest...")
          @backup_forest = I18n::Tasks::BaseTask.new({
            data: {
              read: i18n.data.config[:read].map { |p| p.gsub("config/locales", "i18n_backups") },
              write: i18n.data.config[:write].map { |p| p.gsub("config/locales", "i18n_backups") },
            }
          }).data_forest
        end

        def update_get_keys_from_forest(type, node)
          if node.children.nil?
            @keys[type][node.full_key] = node.value
          else
            node.children.each { |subnode|
              update_get_keys_from_forest(type, subnode)
            }
          end
        end

        def update_check_differences
          @differing = []
          @removed = []
          @added = []
          @keys[:current].each { |k, v|
             if !@keys[:base][k].nil? && @keys[:base][k] != v
              cleaned = k.split(".")
              cleaned.shift
              @differing.push(cleaned.join("."))
            end
          }
          @keys[:base].each { |k, v|
             if @keys[:current][k].nil?
              cleaned = k.split(".")
              cleaned.shift
              @removed.push(cleaned.join("."))
            end
          }
          @keys[:current].each { |k, v|
             if @keys[:base][k].nil?
              cleaned = k.split(".")
              cleaned.shift
              @added.push(cleaned.join("."))
            end
          }
        end

        def update_get_differing_keys
          @keys = {
            current: {},
            base: {}
          }
          update_get_keys_from_forest(:current, @current_forest.get(@base_locale))
          update_get_keys_from_forest(:base, @backup_forest.get(@base_locale))
          update_check_differences
        end

        def update_process_differing_keys
          @locales = i18n.locales.select { |l| l != @base_locale }

          update_log("Found #{@differing.count} differing keys:")
          @differing.each { |k| update_log("  - #{k}") }
          update_log("Found #{@added.count} added keys:")
          @added.each { |k| update_log("  - #{k}") }
          update_log("Found #{@removed.count} removed keys:")
          @removed.each { |k| update_log("  - #{k}") }
          puts ""

          if @differing.count > 0 || @removed.count > 0
            i = 0
            blocked = !@from.nil?

            update_log("Removing differing keys...")
            @differing.each { |k|
              i += 1
              update_log("  #{i} / #{@differing.count} - #{k}")
              @current_forest.mv_key!(compile_key_pattern("#{k}"), '', root: false, except: @except)
            }
            i = 0
            update_log("Removing removed keys...")
            @removed.each { |k|
              i += 1
              update_log("  #{i} / #{@removed.count} - #{k}")
              @current_forest.mv_key!(compile_key_pattern("#{k}"), '', root: false, except: @except)
            }

            i = 0
            update_log("Rewriting locales after removing...")
            i18n.locales.each { |locale|
              i += 1
              update_log("  #{i} / #{@i18n.locales.count} - #{locale}")
              if !@except.include?(locale)
                i18n.data.set(locale, @current_forest.get(locale))
              else
                puts "Ignoring #{locale}"
              end
            }

          end
          if @translate
            update_log("Retrieving differing forest (will take a little while)")

            data = {}
            @differing.each { |k| data[k] = @current_forest.get("#{@base_locale}.#{k}") }
            @added.each { |k| data[k] = @current_forest.get("#{@base_locale}.#{k}") }
            data.each { |k, v| @current_forest.set("en.#{k}", v) }
            i18n.data.set("en", @current_forest.get("en"))

            missing = i18n.missing_diff_forest i18n.locales, "en"
            update_log("Adding and translating added keys...")
            translated = i18n.translate_forest missing, from: "en", backend: :google
            @current_forest.merge! translated
          else
            update_log("Setting every differing / added key to #{@base_locale}...")

            data = {}
            @differing.each { |k| data[k] = @current_forest.get("#{@base_locale}.#{k}") }
            @added.each { |k| data[k] = @current_forest.get("#{@base_locale}.#{k}") }
            @locales.each { |locale|
              if locale != @base_locale
                data.each { |k, v|
                  update_log("Writing #{k} to #{locale}...")
                  @current_forest.set("#{locale}.#{k}", v)
                }
              end
            }
          end
        end

        def update_parse_arguments(opt)
          @translate = true
          @base_locale = "base"
          @export_js = true
          @except = ""
          @from = nil
          opt.each { |arg|
            split = arg.split("=")
            instance_variable_set("@#{split.first}", split.second == "true" || split.second == "false" ? split.second == "true" : split.second)
          }
          if @except != ""
            @except = @except.split(", ") + [@base_locale]
          end
        end

        def update(opt = {})
          update_parse_arguments(opt[:arguments])
          update_update_backups(false)
          update_get_forests
          update_get_differing_keys

          if !(@differing.count == 0 && @added.count == 0 && @removed.count == 0)
            update_process_differing_keys
            update_log("Writing everything back to the files (this will take a while)...")
            i18n.data.write @current_forest
          end
          update_log("Updating backup files")
          update_update_backups(true)
          if @export_js
            update_log("Running js export (will also take a while)...")
            system("rake i18n:js:export")
          end
        end
      end
    end
  end
end
