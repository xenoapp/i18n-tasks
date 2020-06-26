# frozen_string_literal: true

require 'pry'

module I18n::Tasks
  module Command
    module Commands
      module Add
        include Command::Collection
        cmd :update,
            pos:  '[locales key value]',
            desc: "Creates or replaces an existing key if it exists in the locales files"

        def is_new_key(split)
          return false if @in_key && split.select { |s| s.blank? }.count > @current_scope.count
          split = split.last.split(":")
          parsed = [split.first]
          split.shift
          parsed.push(split.join(":"))
          return true if parsed.first.count("'") == 2 && parsed.first[0] == "'" && parsed.first[-1] == "'" && ["'yes'", "'no'", "'true'", "'false'"].include?(parsed.first)
          return parsed.first.count(" \n\t\"'") == 0 && !parsed.second.blank?
        end

        def update_tree(key_buffer = nil, value_buffer = nil)
          if key_buffer
            tmp = key_buffer.split(":")
            key = tmp.last
            current_scope = tmp.first tmp.count - 1
            value = value_buffer
          else
            key = @key
            value = @value
            current_scope = @current_scope
          end
          if !key.blank? && !value.blank?
            anchor = @tree
            current_scope.each { |scope|
              anchor[scope] = {} if anchor[scope].nil?
              anchor = anchor[scope]
            }
            anchor[key] = value
          end
        end

        def is_new_scope(split)
          return false if @in_key && split.select { |s| s.blank? }.count > @current_scope.count
          return split.last[-1] == ":" && split.last.count(":") == 1 && split.last.count(" \n\t\"'") == 0
        end

        def is_different_scope(count)
          return @current_scope.count != count
        end

        def go_to_previous_scope(count)
          @current_scope = count == 0 ? [] : @current_scope.first(count)
        end

        def is_in_key
          return true if @value == "|-" || @value == "|+"
          return true if @value.size == 1 && @value[0] == "'"
          return  @value[0] == "'" && @value[-1] != "'"
        end

        def update_with_new_scope(count, split)
          if count > @current_scope.count - 1 || @current_scope.count == 0
            @current_scope.push(@key)
          elsif count < @current_scope.count
            @current_scope = count == 0 ? [] : @current_scope.first(count)
            @current_scope.push(@key)
          end
        end

        def generate_key_value(new_key, new_scope, split, key_buffer, value_buffer)
          if @in_key && !new_key && !new_scope
            @key = nil
            @value = split.last
          else
            tmp = split.last.split(":")
            @key = tmp.first
            tmp.shift
            @value = tmp.join(":")
            @value = @value == "" ? "" : @value[1,@value.size - 1]
          end
        end

        def write_tree(spaces, section = nil)
          section.each { |k, v|
            if v.is_a? Hash
              @file.write("#{spaces}#{k}:\n")
              write_tree(spaces + "  ", v)
            else
              @file.write("#{spaces}#{k}: #{v}\n")
            end
          }
        end

        def get_split(line)
          split = line.split("  ")
          if split.count > 0
            tmp = []
            tmp_split = split.dup
            tmp_count = 0
            tmp_count += 1 while tmp_split[tmp_count].blank?
            if tmp_count + 1 != tmp_split.count
              tmp.push(tmp_split.shift) while tmp_split.first.blank?
              tmp_last = []
              tmp_last.push(tmp_split.shift) while tmp_split.count > 0
              tmp.push(tmp_last.join("  "))
              split = tmp
            end
          end
          return split
        end

        def get_tree(file_path)
          file = File.open(file_path)
          data = file.readlines
          @tree = {}
          @current_scope = []
          @in_key = false
          key_buffer = ""
          value_buffer = ""
          count_buffer = 0
          data.each { |line|
            line = line[0, line.size - 1]
            if line != "---"
              split = get_split(line)
              new_key = split.count > 0 ? is_new_key(split) : nil
              new_scope = split.count > 0 ? is_new_scope(split) : nil

              if !new_key.nil? && !new_scope.nil?
                generate_key_value(new_key, new_scope, split, key_buffer, value_buffer)
                count = split.select { |s| s.blank? }.count
                can_update_tree = false
                can_update_buffer = true

                if new_scope
                  update_with_new_scope(count, split)
                  if @in_key
                    update_tree(key_buffer, value_buffer)
                    @in_key = false
                  end
                elsif new_key && is_different_scope(count)
                  go_to_previous_scope(count)
                  if @in_key
                    update_tree(key_buffer, value_buffer)
                    @in_key = false
                  end
                end

                if new_key
                  update_tree(key_buffer, value_buffer) if @in_key == true

                  @in_key = is_in_key
                  value_buffer = @in_key ? @value : ""

                  key_buffer = @in_key ? ("#{@current_scope.join(":")}:#{@key}") : ""
                  count_buffer = @in_key ? count : 0
                  can_update_tree = true
                  can_update_buffer = !@in_key
                end

                if !@in_key
                  update_tree if can_update_tree
                else
                  value_buffer = value_buffer + "\n" + line if can_update_buffer
                end
              else
                value_buffer = value_buffer + "\n" + line if @in_key
              end
            end
          }
        end

        def rewrite_tree(file_path)
          tmp_file = file_path.gsub("/", "_")
          @file = File.open("/tmp/#{tmp_file}", "w")
          @file.write("---\n#{@locale}:\n")
          write_tree("  ", @tree[@locale])
          @file.close
          system("mv #{file_path} /tmp/backup_#{tmp_file} && cp /tmp/#{tmp_file} #{file_path}")
        end

        def tree_contains(key)
          anchor = @tree[@locale]
          key.each { |k|
            return false if anchor[k].nil?
            anchor = anchor[k]
          }
          return true
        end

        def put_in_tree(key, value)
          if tree_contains(key)
            puts "WARNING: #{key.join(".")} already exists, replacing it"
          end
          anchor = @tree[@locale]
          key.first(key.count - 1).each { |k|
            anchor[k] = {} if anchor[k].nil?
            anchor = anchor[k]
          }
          quotes = value.count("!") > 0 ? "'" : ""
          anchor[key.last] = ""

          split_value = value.split("\n")
          spacing = ""
          if split_value.count > 1
            anchor[key.last] = "|-\n"
            spacing = "  " * (key.count + 1)
          end
          split_value.each { |v|
            anchor[key.last] += "#{spacing}#{v}\n"
          }
          anchor[key.last] = "#{quotes}#{anchor[key.last][0,anchor[key.last].size - 1]}#{quotes}"
          puts "=> #{key.join(".")}"
        end

        def update(opt = {})
          section = opt[:arguments].first
          locales = opt[:arguments].second.split(',')
          key = opt[:arguments].third.split(".")
          value = opt[:arguments].fourth

          locales.each { |locale|
            @locale = locale
            i18n.data.config[:read].each { |file_path|
              file_path = file_path.sub("%{locale}", locale)
              if file_path.match(section)
                get_tree(file_path)
                put_in_tree(key, value)
                rewrite_tree(file_path)
                return
              end
            }
          }
          puts "Unknown section <#{section}>"
        end
      end
    end
  end
end
