module FlowChat
  module Ussd
    module Middleware
      class Pagination
        def initialize(app)
          @app = app
          FlowChat.logger.debug { "Ussd::Pagination: Initialized USSD pagination middleware" }
        end

        def call(context)
          @context = context
          @session = context.session

          session_id = context["session.id"]
          FlowChat.logger.debug { "Ussd::Pagination: Processing request for session #{session_id}" }

          if intercept?
            FlowChat.logger.info { "Ussd::Pagination: Intercepting request for pagination handling - session #{session_id}" }
            type, prompt = handle_intercepted_request
            [type, prompt, []]
          else
            # Clear pagination state for new flows
            if pagination_state.present?
              FlowChat.logger.debug { "Ussd::Pagination: Clearing pagination state for new flow - session #{session_id}" }
            end
            @session.delete "ussd.pagination"
            
            type, prompt, choices, media = @app.call(context)

            prompt = FlowChat::Ussd::Renderer.new(prompt, choices: choices, media: media).render
            
            if prompt.present?
              original_length = prompt.length
              type, prompt = maybe_paginate(type, prompt)
              if prompt.length != original_length
                FlowChat.logger.info { "Ussd::Pagination: Content paginated - original: #{original_length} chars, paginated: #{prompt.length} chars" }
              end
            end

            [type, prompt, []]
          end
        end

        private

        def intercept?
          should_intercept = pagination_state.present? &&
            (pagination_state["type"].to_sym == :terminal ||
             ([FlowChat::Config.ussd.pagination_next_option, FlowChat::Config.ussd.pagination_back_option].include? @context.input))
          
          if should_intercept
            FlowChat.logger.debug { "Ussd::Pagination: Intercepting - input: #{@context.input}, pagination type: #{pagination_state["type"]}" }
          end
          
          should_intercept
        end

        def handle_intercepted_request
          FlowChat.logger.info { "Ussd::Pagination: Handling paginated request" }
          start, finish, has_more = calculate_offsets
          type = (pagination_state["type"].to_sym == :terminal && !has_more) ? :terminal : :prompt
          prompt = pagination_state["prompt"][start..finish] + build_pagination_options(type, has_more)
          set_pagination_state(current_page, start, finish)

          FlowChat.logger.debug { "Ussd::Pagination: Serving page content - start: #{start}, finish: #{finish}, has_more: #{has_more}, type: #{type}" }
          [type, prompt]
        end

        def maybe_paginate(type, prompt)
          if prompt.length > FlowChat::Config.ussd.pagination_page_size
            original_prompt = prompt
            FlowChat.logger.info { "Ussd::Pagination: Content exceeds page size (#{prompt.length} > #{FlowChat::Config.ussd.pagination_page_size}), initiating pagination" }
            
            slice_end = single_option_slice_size
            # Ensure we do not cut words and options off in the middle.
            current_pagebreak = original_prompt[slice_end + 1].blank? ? slice_end : original_prompt[0..slice_end].rindex("\n") || original_prompt[0..slice_end].rindex(" ") || slice_end
            
            FlowChat.logger.debug { "Ussd::Pagination: First page break at position #{current_pagebreak}" }
            
            set_pagination_state(1, 0, current_pagebreak, original_prompt, type)
            prompt = original_prompt[0..current_pagebreak] + "\n\n" + next_option
            type = :prompt
            
            FlowChat.logger.debug { "Ussd::Pagination: First page prepared with #{prompt.length} characters" }
          end
          [type, prompt]
        end

        def calculate_offsets
          page = current_page
          
          FlowChat.logger.debug { "Ussd::Pagination: Calculating offsets for page #{page}" }
          
          offset = pagination_state["offsets"][page.to_s]
          if offset.present?
            FlowChat.logger.debug { "Ussd::Pagination: Using cached offset for page #{page}" }
            start = offset["start"]
            finish = offset["finish"]
            has_more = pagination_state["prompt"].length > finish
          else
            FlowChat.logger.debug { "Ussd::Pagination: Computing new offset for page #{page}" }
            # We are guaranteed a previous offset because it was set in maybe_paginate
            previous_page = page - 1
            previous_offset = pagination_state["offsets"][previous_page.to_s]
            start = previous_offset["finish"] + 1
            has_more, len = (pagination_state["prompt"].length > start + single_option_slice_size) ? [true, dual_options_slice_size] : [false, single_option_slice_size]
            finish = start + len
            
            if start > pagination_state["prompt"].length
              FlowChat.logger.warn { "Ussd::Pagination: No content for page #{page}, reverting to page #{page - 1}" }
              page -= 1
              has_more = false
              start = previous_offset["start"]
              finish = previous_offset["finish"]
            else
              # Apply word boundary logic for the new page
              full_prompt = pagination_state["prompt"]
              if finish < full_prompt.length
                # Look for word boundary within the slice
                slice_text = full_prompt[start..finish]
                # Check if the character after our slice point is a word boundary
                next_char = full_prompt[finish + 1]
                if next_char && !next_char.match(/\s/)
                  # We're in the middle of a word, find the last word boundary
                  boundary_pos = slice_text.rindex("\n") || slice_text.rindex(" ")
                  if boundary_pos
                    old_finish = finish
                    finish = start + boundary_pos
                    FlowChat.logger.debug { "Ussd::Pagination: Adjusted finish for word boundary - #{old_finish} -> #{finish}" }
                  end
                  # If no boundary found, we'll have to break mid-word (fallback)
                end
              end
            end
          end
          
          FlowChat.logger.debug { "Ussd::Pagination: Page #{page} offsets - start: #{start}, finish: #{finish}, has_more: #{has_more}" }
          [start, finish, has_more]
        end

        def build_pagination_options(type, has_more)
          options_str = ""
          has_less = current_page > 1
          
          FlowChat.logger.debug { "Ussd::Pagination: Building pagination options - type: #{type}, has_more: #{has_more}, has_less: #{has_less}" }
          
          if type.to_sym == :prompt
            options_str += "\n\n"
            next_opt = has_more ? next_option : ""
            back_opt = has_less ? back_option : ""
            options_str += [next_opt, back_opt].join("\n").strip
          end
          options_str
        end

        def next_option
          "#{FlowChat::Config.ussd.pagination_next_option} #{FlowChat::Config.ussd.pagination_next_text}"
        end

        def back_option
          "#{FlowChat::Config.ussd.pagination_back_option} #{FlowChat::Config.ussd.pagination_back_text}"
        end

        def single_option_slice_size
          unless @single_option_slice_size.present?
            # To display a single back or next option
            # We accomodate the 2 newlines and the longest of the options
            # We subtract an additional 1 to normalize it for slicing
            @single_option_slice_size = FlowChat::Config.ussd.pagination_page_size - 2 - [next_option.length, back_option.length].max - 1
            FlowChat.logger.debug { "Ussd::Pagination: Calculated single option slice size: #{@single_option_slice_size}" }
          end
          @single_option_slice_size
        end

        def dual_options_slice_size
          unless @dual_options_slice_size.present?
            # To display both back and next options
            # We accomodate the 3 newlines and both of the options
            @dual_options_slice_size = FlowChat::Config.ussd.pagination_page_size - 3 - [next_option.length, back_option.length].sum - 1
            FlowChat.logger.debug { "Ussd::Pagination: Calculated dual options slice size: #{@dual_options_slice_size}" }
          end
          @dual_options_slice_size
        end

        def current_page
          page = pagination_state["page"]
          if @context.input == FlowChat::Config.ussd.pagination_back_option
            page -= 1
            FlowChat.logger.debug { "Ussd::Pagination: Moving to previous page: #{page}" }
          elsif @context.input == FlowChat::Config.ussd.pagination_next_option
            page += 1
            FlowChat.logger.debug { "Ussd::Pagination: Moving to next page: #{page}" }
          end
          [page, 1].max
        end

        def pagination_state
          @context.session.get("ussd.pagination") || {}
        end

        def set_pagination_state(page, offset_start, offset_finish, prompt = nil, type = nil)
          current_state = pagination_state
          offsets = current_state["offsets"] || {}
          offsets[page.to_s] = {"start" => offset_start, "finish" => offset_finish}
          prompt ||= current_state["prompt"]
          type ||= current_state["type"]
          new_state = {
            "page" => page,
            "offsets" => offsets,
            "prompt" => prompt,
            "type" => type.to_s
          }
          
          FlowChat.logger.debug { "Ussd::Pagination: Saving pagination state - page: #{page}, total_content: #{prompt&.length || 0} chars" }
          @session.set "ussd.pagination", new_state
        end
      end
    end
  end
end
