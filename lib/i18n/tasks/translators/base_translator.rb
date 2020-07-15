# frozen_string_literal: true

require('unicode/emoji')

module I18n::Tasks
  module Translators
    class BaseTranslator
      # @param [I18n::Tasks::BaseTask] i18n_tasks
      def initialize(i18n_tasks)
        @i18n_tasks = i18n_tasks
      end

      # @param [I18n::Tasks::Tree::Siblings] forest to translate to the locales of its root nodes
      # @param [String] from locale
      # @return [I18n::Tasks::Tree::Siblings] translated forest
      def translate_forest(forest, from)
        sleep_span = 90
        error = false

        forest = forest.inject @i18n_tasks.empty_forest do |result, root|
          if root.key != from && error == false
            puts "Translating #{root.key}..."
            retries = 0
            translated = nil
            begin
              translated = translate_pairs(root.key_values(root: true), to: root.key, from: from)
            rescue Exception => e
              if retries > 2
                puts "ERROR: #{e.message}"
                error = true
              else
                puts "  Got an exception (#{e.message}), sleeping"
                sleep sleep_span
                puts "  Retrying"
                retries += 1
                retry
              end
            end
            puts "OK"
            result.merge! Data::Tree::Siblings.from_flat_pairs(translated)
          end
          result
        end
        puts "Done! Writing stuff (may take a while)"
        forest
      end

      protected

      # @param [Array<[String, Object]>] list of key-value pairs
      # @return [Array<[String, Object]>] translated list
      def translate_pairs(list, opts)
        return [] if list.empty?
        opts = opts.dup
        key_pos = list.each_with_index.inject({}) { |idx, ((k, _v), i)| idx.update(k => i) }
        # copy reference keys as is, instead of translating
        reference_key_vals = list.select { |_k, v| v.is_a? Symbol } || []
        list -= reference_key_vals
        result = list.group_by { |k_v| @i18n_tasks.html_key?(k_v[0], opts[:from]) || @i18n_tasks.html_value?(k_v[1], opts[:from]) }.map do |is_html, list_slice|
          fetch_translations list_slice, opts.merge(is_html ? options_for_html : options_for_plain)
        end.reduce(:+) || []
        result.concat(reference_key_vals)
        result.sort! { |a, b| key_pos[a[0]] <=> key_pos[b[0]] }
        result
      end

      # @param [Array<[String, Object]>] list of key-value pairs
      # @return [Array<[String, Object]>] translated list
      def fetch_translations(list, opts)
        from_values(list, translate_values(to_values(list), **options_for_translate_values(**opts))).tap do |result|
          fail CommandError, no_results_error_message if result.blank?
        end
      end

      # @param [Array<[String, Object]>] list of key-value pairs
      # @return [Array<String>] values for translation extracted from list
      def to_values(list)
        list.map { |l| dump_value l[1] }.flatten.compact
      end

      # @param [Array<[String, Object]>] list
      # @param [Array<String>] translated_values
      # @return [Array<[String, Object]>] translated key-value pairs
      def from_values(list, translated_values)
        keys = list.map(&:first)
        untranslated_values = list.map(&:last)
        keys.zip parse_value(untranslated_values, translated_values.to_enum)
      end

      # Prepare value for translation.
      # @return [String, Array<String, nil>, nil] value for Google Translate or nil for non-string values
      def dump_value(value)
        case value
        when Array
          # dump recursively
          value.map { |v| dump_value v }
        when String
          replace_interpolations value unless value.empty?
        end
      end

      # Parse translated value from the each_translated enumerator
      # @param [Object] untranslated
      # @param [Enumerator] each_translated
      # @return [Object] final translated value
      def parse_value(untranslated, each_translated)
        case untranslated
        when Array
          # implode array
          untranslated.map { |from| parse_value(from, each_translated) }
        when String
          if untranslated.empty?
            untranslated
          else
            restore_interpolations untranslated, each_translated.next
          end
        else
          untranslated
        end
      end

      def get_interpolation_key_regex
        return /%\{[^}]+}|:[^ ]*:|<[^>]+>|\n\r|\n|#{Unicode::Emoji::REGEX}/
      end

      UNTRANSLATABLE_STRING = 'zxzxzx'
      UNTRANSLATABLE_STRING_REG = '[zZ][xX][zZ][xX][zZ][xX]'

      def get_untranslatable_string_interpolation_regex(nb = nil, negative = false)
        if nb.nil?
          /#{UNTRANSLATABLE_STRING_REG}#{negative ? /-?/ : //}\d+/i
        else
          /#{UNTRANSLATABLE_STRING_REG}#{negative ? /-?/ : //}#{nb}/i
        end
      end

      def get_interpolation_spans(value)
        indexes = []
        value.scan(get_untranslatable_string_interpolation_regex).each { |m| indexes.push(value.index(m)) }

        from = -1
        to = -1
        spans = []
        indexes.each_with_index { |idx, i|
          if i > 0
            if indexes[i - 1] + UNTRANSLATABLE_STRING.length + (i - 1).to_s.length == idx
              from = i - 1 if from == -1
              to = i
            else
              if to != -1
                spans.push({from: from, to: to})
                from = -1
                to = -1
              end
            end
          end
        }
        spans.push({from: from, to: to}) if from != -1 && to != -1
        singles = []
        indexes.each_with_index { |idx, i|
          found = false
          spans.each { |span|
            if !found && i >= span[:from] && i <= span[:to]
              found = true
            end
          }
          singles.push({from: i, to: i}) if !found
        }
        spans = spans + singles
        spans.sort do |a, b| a[:from] <=> b[:from] end
      end

      def get_interpolation_string(i)
        "#{UNTRANSLATABLE_STRING}#{i}"
      end

      # @param [String] value
      # @return [String] 'hello, %{name}' => 'hello, <round-trippable string>'
      def replace_interpolations(value, concat_interpolations = true)
        i = -1

        @raw_values = []
        new_value = value.gsub get_interpolation_key_regex do |m|
          i += 1
          @raw_values.push(m)
          get_interpolation_string(i)
        end

        if concat_interpolations == true
          spans = get_interpolation_spans(new_value)
          @concat_raw_values = []
          spans.each { |span|
            tmp = ""
            (span[:from]..span[:to]).each do |i|
              tmp += @raw_values[i]
            end
            @concat_raw_values.push(tmp)
          }

          spans.each { |span|
            i += 1
            if span[:from] == span[:to]
              new_value = new_value.gsub(get_untranslatable_string_interpolation_regex(span[:from]), get_interpolation_string(-1 * i))
            else
              new_value = new_value.gsub(/#{Regexp.escape(UNTRANSLATABLE_STRING)}#{span[:from]}.*?#{Regexp.escape(UNTRANSLATABLE_STRING)}#{span[:to]}/, get_interpolation_string(i))
            end
          }
          i = -1

          new_value = new_value.gsub(get_untranslatable_string_interpolation_regex(nil, true)) do |m|
            i += 1
            @has_translate_no = true
            "<span translate=\"no\">#{get_interpolation_string(i)}</span>"
          end
        end
        new_value
      end

      def get_member_from_interpolation_regex(m)
        return m[(m.index(UNTRANSLATABLE_STRING))..-8]
      end

      def get_values_from_unconcatenated_value(untranslated, translated)
        translated = restore_code(translated)
        raw_values = untranslated.scan(get_interpolation_key_regex)
        not_concat = replace_interpolations(untranslated, false)
        spans = get_interpolation_spans(not_concat)
        values = []

        spans.each { |span|
          tmp = ""
          (span[:from]..span[:to]).each do |i|
            tmp += raw_values[i]
          end
          values.push(tmp)
        }
        values
      end

      # @param [String] untranslated
      # @param [String] translated
      # @return [String] 'hello, <round-trippable string>' => 'hello, %{name}'
      def restore_interpolations(untranslated, translated)
        return translated if untranslated !~ get_interpolation_key_regex

        template = replace_interpolations(untranslated)
        new_translated = translated.gsub(/<span translate=\"no\">#{get_untranslatable_string_interpolation_regex}<\/span>/) do |m| get_member_from_interpolation_regex(m) end
        template = template.gsub(/<span translate=\"no\">#{get_untranslatable_string_interpolation_regex}<\/span>/) do |m| get_member_from_interpolation_regex(m) end

        template.scan(/#{Regexp.escape(UNTRANSLATABLE_STRING)}\d+/i).each { |m|
          template_idx = template.index(m)
          new_translated_idx = new_translated.index(m)

          if new_translated[new_translated_idx + m.length] == ' ' && template[template_idx + m.length] != ' '
            new_translated = new_translated[0, new_translated_idx + m.length] + new_translated[new_translated_idx + m.length + 1, new_translated.length]
            new_translated_idx = new_translated.index(m)
          end
          if new_translated[new_translated_idx - 1] == ' ' && template[template_idx - 1] != ' '
            new_translated = new_translated[0, new_translated_idx - 1] + new_translated[new_translated_idx, new_translated.length]
          end
        }
        new_translated = new_translated.gsub(/#{Regexp.escape(UNTRANSLATABLE_STRING)}\d+/i) do |m|
          @concat_raw_values[m[UNTRANSLATABLE_STRING.length..-1].to_i]
        end
        new_translated
      # rescue StandardError => e
      #   raise_interpolation_error(untranslated, translated, e)
      end

      def raise_interpolation_error(untranslated, translated, e)
        fail CommandError.new(e, <<~TEXT.strip)
          Error when restoring interpolations:
            original: "#{untranslated}"
            response: "#{translated}"
            error: #{e.message} (#{e.class.name})
        TEXT
      end

      # @param [Array<String>] list
      # @param [Hash] options
      # @return [Array<String>]
      # @abstract
      def translate_values(list, **options); end

      # @param [Hash] options
      # @return [Hash]
      # @abstract
      def options_for_translate_values(options); end

      # @return [Hash]
      # @abstract
      def options_for_html; end

      # @return [Hash]
      # @abstract
      def options_for_plain; end

      # @return [String]
      # @abstract
      def no_results_error_message; end
    end
  end
end
