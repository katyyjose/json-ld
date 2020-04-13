# -*- encoding: utf-8 -*-
# frozen_string_literal: true
module JSON::LD
  module Compact
    include Utils

    # The following constant is used to reduce object allocations in #compact below
    CONTAINER_MAPPING_LANGUAGE_INDEX_ID_TYPE = Set.new(%w(@language @index @id @type)).freeze
    EXPANDED_PROPERTY_DIRECTION_INDEX_LANGUAGE_VALUE = %w(@direction @index @language @value).freeze

    ##
    # This algorithm compacts a JSON-LD document, such that the given context is applied. This must result in shortening any applicable IRIs to terms or compact IRIs, any applicable keywords to keyword aliases, and any applicable JSON-LD values expressed in expanded form to simple values such as strings or numbers.
    #
    # @param [Array, Hash] element
    # @param [String] property (nil)
    # @param [Boolean] ordered (true)
    #   Ensure output objects have keys ordered properly
    # @return [Array, Hash]
    def compact(element, property: nil, ordered: false)
      #if property.nil?
      #  log_debug("compact") {"element: #{element.inspect}, ec: #{context.inspect}"}
      #else
      #  log_debug("compact") {"property: #{property.inspect}"}
      #end

      # If the term definition for active property itself contains a context, use that for compacting values.
      input_context = self.context

      case element
      when Array
        #log_debug("") {"Array #{element.inspect}"}
        result = element.map {|item| compact(item, property: property, ordered: ordered)}.compact

        # If element has a single member and the active property has no
        # @container mapping to @list or @set, the compacted value is that
        # member; otherwise the compacted value is element
        if result.length == 1 &&
           !context.as_array?(property) && @options[:compactArrays]
          #log_debug("=> extract single element: #{result.first.inspect}")
          result.first
        else
          #log_debug("=> array result: #{result.inspect}")
          result
        end
      when Hash
        # Otherwise element is a JSON object.

        # @null objects are used in framing
        return nil if element.key?('@null')

        # Revert any previously type-scoped (non-preserved) context
        if context.previous_context && !element.key?('@value') && element.keys != %w(@id)
          self.context = context.previous_context
        end

        # Look up term definintions from property using the original type-scoped context, if it exists, but apply them to the now current previous context
        td = input_context.term_definitions[property] if property
        self.context = context.parse(td.context, override_protected: true) if td && !td.context.nil?

        if element.key?('@id') || element.key?('@value')
          result = context.compact_value(property, element, log_depth: @options[:log_depth])
          if !result.is_a?(Hash) || context.coerce(property) == '@json'
            #log_debug("") {"=> scalar result: #{result.inspect}"}
            return result
          end
        end

        # If expanded property is @list and we're contained within a list container, recursively compact this item to an array
        if list?(element) && context.container(property).include?('@list')
          return compact(element['@list'], property: property, ordered: ordered)
        end

        inside_reverse = property == '@reverse'
        result, nest_result = {}, nil

        # Apply any context defined on an alias of @type
        # If key is @type and any compacted value is a term having a local context, overlay that context.
        Array(element['@type']).
          map {|expanded_type| context.compact_iri(expanded_type, vocab: true)}.
          sort.
          each do |term|
          term_context = input_context.term_definitions[term].context if input_context.term_definitions[term]
          self.context = context.parse(term_context, propagate: false) unless term_context.nil?
        end

        element.keys.opt_sort(ordered: ordered).each do |expanded_property|
          expanded_value = element[expanded_property]
          #log_debug("") {"#{expanded_property}: #{expanded_value.inspect}"}

          if expanded_property == '@id'
            compacted_value = Array(expanded_value).map {|expanded_id| context.compact_iri(expanded_id)}

            kw_alias = context.compact_iri('@id', vocab: true)
            as_array = compacted_value.length > 1
            compacted_value = compacted_value.first unless as_array
            result[kw_alias] = compacted_value
            next
          end

          if expanded_property == '@type'
            compacted_value = Array(expanded_value).map {|expanded_type| input_context.compact_iri(expanded_type, vocab: true)}

            kw_alias = context.compact_iri('@type', vocab: true)
            as_array = compacted_value.length > 1 ||
                       (context.as_array?(kw_alias) &&
                        !value?(element) &&
                        context.processingMode('json-ld-1.1'))
            add_value(result, kw_alias, compacted_value, property_is_array: as_array)
            next
          end

          if expanded_property == '@reverse'
            compacted_value = compact(expanded_value, property: '@reverse', ordered: ordered)
            #log_debug("@reverse") {"compacted_value: #{compacted_value.inspect}"}
            # handle double-reversed properties
            compacted_value.each do |prop, value|
              if context.reverse?(prop)
                add_value(result, prop, value,
                  property_is_array: context.as_array?(prop) || !@options[:compactArrays])
                compacted_value.delete(prop)
              end
            end

            unless compacted_value.empty?
              al = context.compact_iri('@reverse')
              #log_debug("") {"remainder: #{al} => #{compacted_value.inspect}"}
              result[al] = compacted_value
            end
            next
          end

          if expanded_property == '@preserve'
            # Compact using `property`
            compacted_value = compact(expanded_value, property: property, ordered: ordered)
            #log_debug("@preserve") {"compacted_value: #{compacted_value.inspect}"}

            unless compacted_value.is_a?(Array) && compacted_value.empty?
              result['@preserve'] = compacted_value
            end
            next
          end

          if expanded_property == '@index' && context.container(property).include?('@index')
            #log_debug("@index") {"drop @index"}
            next
          end

          # Otherwise, if expanded property is @direction, @index, @value, or @language:
          if EXPANDED_PROPERTY_DIRECTION_INDEX_LANGUAGE_VALUE.include?(expanded_property)
            al = context.compact_iri(expanded_property, vocab: true)
            #log_debug(expanded_property) {"#{al} => #{expanded_value.inspect}"}
            result[al] = expanded_value
            next
          end

          if expanded_value.empty?
            item_active_property =
              context.compact_iri(expanded_property,
                                  value: expanded_value,
                                  vocab: true,
                                  reverse: inside_reverse,
                                  log_depth: @options[:log_depth])

            if nest_prop = context.nest(item_active_property)
              result[nest_prop] ||= {}
              add_value(result[nest_prop], item_active_property, [],
                property_is_array: true)
            else
              add_value(result, item_active_property, [],
                property_is_array: true)
            end
          end

          # At this point, expanded value must be an array due to the Expansion algorithm.
          expanded_value.each do |expanded_item|
            item_active_property =
              context.compact_iri(expanded_property,
                                  value: expanded_item,
                                  vocab: true,
                                  reverse: inside_reverse,
                                  log_depth: @options[:log_depth])


            nest_result = if nest_prop = context.nest(item_active_property)
              # FIXME??: It's possible that nest_prop will be used both for nesting, and for values of @nest
              result[nest_prop] ||= {}
            else
              result
            end

            container = context.container(item_active_property)
            as_array = !@options[:compactArrays] || context.as_array?(item_active_property)

            value = case
            when list?(expanded_item) then expanded_item['@list']
            when graph?(expanded_item) then expanded_item['@graph']
            else expanded_item
            end

            compacted_item = compact(value, property: item_active_property, ordered: ordered)
            #log_debug("") {" => compacted key: #{item_active_property.inspect} for #{compacted_item.inspect}"}

            # handle @list
            if list?(expanded_item)
              compacted_item = as_array(compacted_item)
              unless container.include?('@list')
                al = context.compact_iri('@list', vocab: true)
                compacted_item = {al => compacted_item}
                if expanded_item.has_key?('@index')
                  key = context.compact_iri('@index', vocab: true)
                  compacted_item[key] = expanded_item['@index']
                end
              else
                add_value(nest_result, item_active_property, compacted_item,
                  value_is_array: true, allow_duplicate: true)
                  next
              end
            end

            # Graph object compaction cases:
            if graph?(expanded_item)
              if container.include?('@graph') &&
                (container.include?('@id') || container.include?('@index') && simple_graph?(expanded_item))
                # container includes @graph and @id
                map_object = nest_result[item_active_property] ||= {}
                # If there is no @id, create a blank node identifier to use as an index
                map_key = if container.include?('@id') && expanded_item['@id']
                  context.compact_iri(expanded_item['@id'])
                elsif container.include?('@index') && expanded_item['@index']
                  context.compact_iri(expanded_item['@index'])
                else
                  context.compact_iri('@none', vocab: true)
                end
                add_value(map_object, map_key, compacted_item,
                  property_is_array: as_array)
              elsif container.include?('@graph') && simple_graph?(expanded_item)
                # container includes @graph but not @id or @index and value is a simple graph object
                if compacted_item.is_a?(Array) && compacted_item.length > 1
                  # Mutple objects in the same graph can't be represented directly, as they would be interpreted as two different graphs. Need to wrap in @included.
                  included_key = context.compact_iri('@included', vocab: true)
                  compacted_item = {included_key => compacted_item}
                end
                # Drop through, where compacted_item will be added
                add_value(nest_result, item_active_property, compacted_item,
                  property_is_array: as_array)
              else
                # container does not include @graph or otherwise does not match one of the previous cases, redo compacted_item
                al = context.compact_iri('@graph', vocab: true)
                compacted_item = {al => compacted_item}
                if expanded_item['@id']
                  al = context.compact_iri('@id', vocab: true)
                  compacted_item[al] = context.compact_iri(expanded_item['@id'], vocab: false)
                end
                if expanded_item.has_key?('@index')
                  key = context.compact_iri('@index', vocab: true)
                  compacted_item[key] = expanded_item['@index']
                end
                add_value(nest_result, item_active_property, compacted_item,
                  property_is_array: as_array)
              end
            elsif container.intersect?(CONTAINER_MAPPING_LANGUAGE_INDEX_ID_TYPE) && !container.include?('@graph')
              map_object = nest_result[item_active_property] ||= {}
              c = container.first
              container_key = context.compact_iri(c, vocab: true)
              compacted_item = case
              when container.include?('@id')
                map_key = compacted_item[container_key]
                compacted_item.delete(container_key)
                compacted_item
              when container.include?('@index')
                index_key = context.term_definitions[item_active_property].index || '@index'
                if index_key == '@index'
                  map_key = expanded_item['@index']
                else
                  container_key = context.compact_iri(index_key, vocab: true)
                  map_key, *others = Array(compacted_item[container_key])
                  if map_key.is_a?(String)
                    case others.length
                    when 0 then compacted_item.delete(container_key)
                    when 1 then compacted_item[container_key] = others.first
                    else        compacted_item[container_key] = others
                    end
                  else
                    map_key = context.compact_iri('@none', vocab: true)
                  end
                end
                # Note, if compacted_item is a node reference and key is @id-valued, then this could be compacted further.
                compacted_item
              when container.include?('@language')
                map_key = expanded_item['@language']
                value?(expanded_item) ? expanded_item['@value'] : compacted_item
              when container.include?('@type')
                map_key, *types = Array(compacted_item[container_key])
                case types.length
                when 0 then compacted_item.delete(container_key)
                when 1 then compacted_item[container_key] = types.first
                else        compacted_item[container_key] = types
                end

                # if compacted_item contains a single entry who's key maps to @id, then recompact the item without @type
                if compacted_item.keys.length == 1 && expanded_item.keys.include?('@id')
                  compacted_item = compact({'@id' => expanded_item['@id']}, property: item_active_property)
                end
                compacted_item
              end
              map_key ||= context.compact_iri('@none', vocab: true)
              add_value(map_object, map_key, compacted_item,
                property_is_array: as_array)
            else
              add_value(nest_result, item_active_property, compacted_item,
                property_is_array: as_array)
            end
          end
        end

        result
      else
        # For other types, the compacted value is the element value
        #log_debug("compact") {element.class.to_s}
        element
      end

    ensure
      self.context = input_context
    end
  end
end
