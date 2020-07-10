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
          ["en"].each { |locale|
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

        def update_get_differing_keys
          @keys = {
            current: {},
            backup: {}
          }
          update_get_keys_from_forest(:current, @current_forest.get(@base_locale))
          update_get_keys_from_forest(:backup, @backup_forest.get(@base_locale))
          update_check_differences
        end

        def update_process_differing_keys
          @locales = i18n.locales

          update_log("Found #{@differing.count} differing keys:")
          @differing.each { |k|
            update_log("  - #{k}")
          }
          update_log("Found #{@added.count} added keys:")
          @added.each { |k|
            update_log("  - #{k}")
          }
          update_log("Found #{@removed.count} removed keys:")
          @removed.each { |k|
            update_log("  - #{k}")
          }
          puts ""

          if @differing.count > 0 || @removed.count > 0
            i = 0
            @locales.each { |locale|
              i += 1
              if locale != @base_locale
                something_changed = false
                update_log("#{locale} (#{i} / #{@locales.count}):")
                if @differing.count > 0
                  update_log("  Removing differing keys...")
                    @differing.each { |k|
                    @current_forest.mv_key!(compile_key_pattern("#{locale}.#{k}"), '', root: true)
                    something_changed = true
                  }
                end
                if @removed.count > 0
                  update_log("  Removing removed keys...")
                  @removed.each { |k|
                    @current_forest.mv_key!(compile_key_pattern("#{locale}.#{k}"), '', root: true)
                    something_changed = true
                  }
                end
                if something_changed
                  update_log("  Rewriting locale after removing...")
                  i18n.data.set(locale, @current_forest.get(locale))
                end
              end
            }
          end
          if @translate
            update_log("Retrieving differing forest (will take a little while")
            missing = i18n.missing_diff_forest i18n.locales, @base_locale
            update_log("Adding and translating added keys...")
            translated = i18n.translate_forest missing, from: @base_locale, backend: :google
            @current_forest.merge! translated
          else
            update_log("Setting every differing / added key to #{@base_locale}...")

            data = {}
            @differing.each { |k|
              data[k] = @current_forest.get("en.#{k}")
            }
            @added.each { |k|
              data[k] = @current_forest.get("en.#{k}")
            }
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
          @base_locale = "en"
          @export_js = false
          opt.each { |arg|
            split = arg.split("=")
            instance_variable_set("@#{split.first}", split.second == "true" || split.second == "false" ? split.second == "true" : split.second)
          }
        end

        def update(opt = {})
          update_parse_arguments(opt[:arguments])
          # update_update_backups(false)
          update_get_forests
          update_get_differing_keys

          if !(@differing.count == 0 && @added.count == 0 && @removed.count == 0)
            update_process_differing_keys
            update_log("Writing everything back to the files (this will take a while)...")
            i18n.data.write @current_forest
          end
          # update_update_backups(true)
          if @export_js
            update_log("Running js export (will also take a while)...")
            system("rake i18n:js:export")
          end
        end

        cmd :translate_html,
            pos:  '[locales key value]',
            desc: "Creates or replaces an existing key if it exists in the locales files"



        def translate_get_html_keys_from_forest(node)
          if node.children.nil?
            @keys[node.full_key] = node.value if node.value.count("<>") > 0
          else
            node.children.each { |subnode|
              translate_get_html_keys_from_forest(subnode)
            }
          end
        end

        def translate_html(opt = {})
          @tree = i18n.data_forest
          @keys = {}
          translate_get_html_keys_from_forest(@tree.get("en"))
          i18n.locales.each { |locale|
            if locale != "fr"
              @keys.each { |k, v|
                split = k.split(".")
                split.shift
                k = ([locale] + split).join(".")
                puts "#{locale} -> #{k}"
                @tree.mv_key!(compile_key_pattern("#{locale}.#{k}"), '', root: true)
              }
              puts "Rewriting"
              i18n.data.set(locale, @tree.get(locale))
            end
          }
          puts "Translating missing"
          translated = i18n.translate_forest missing, from: "en", backend: :google
          @tree.merge! translated
          i18n.data.write @tree
        end
      end
    end
  end
end
