# frozen_string_literal: true
require 'pry'

module I18n::Tasks
  module Command
    module Commands
      module Remove
        include Command::Collection
        cmd :remove,
            pos: '[key...]',
            desc: 'removes key'

        class RemoveCommand
          def log(str)
            puts "[ I18n-tasks ] #{str}"
          end

          def parse_arguments(opt)
            @keys = []
            @except = ""
            opt.each { |arg|
              if arg.count("=") > 0
                split = arg.split("=")
                instance_variable_set("@#{split.first}", split.second == "true" || split.second == "false" ? split.second == "true" : split.second)
              else
                @keys.push(arg)
              end
            }
            @except = @except.split(",")
          end

          def process(opt)
            parse_arguments(opt[:arguments])
            log("Retrieving tree")
            @current_forest = i18n.data_forest

            i18n.locales.each { |locale|
              log("#{locale}:")
              if !@except.include?(locale)
                @keys.each { |k|
                  log("Removing #{k}...")
                  @current_forest.mv_key!(compile_key_pattern("#{locale}.#{k}"), '', root: true)
                }
              else
                log("Skipping for #{locale}")
              end
            }
            log("Writing everything back to the files (this will take a while)...")
            i18n.data.write @current_forest
          end
        end

        def remove(opt = {})
          RemoveCommand.new.process(opt)
        end
      end
    end
  end
end
