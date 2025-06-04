module FlowChat
  module Ussd
    module Middleware
      class Pagination
        def initialize(app)
          @app = app
        end

        def call(context)
          @context = context
          @session = context.session

          if intercept?
            type, prompt = handle_intercepted_request
            [type, prompt, []]
          else
            @session.delete "ussd.pagination"
            type, prompt, choices = @app.call(context)

            prompt = FlowChat::Ussd::Renderer.new(prompt, choices).render
            type, prompt = maybe_paginate(type, prompt) if prompt.present?

            [type, prompt, []]
          end
        end

        private

        def intercept?
          pagination_state.present? &&
            (pagination_state["type"].to_sym == :terminal ||
             ([FlowChat::Config.ussd.pagination_next_option, FlowChat::Config.ussd.pagination_back_option].include? @context.input))
        end

        def handle_intercepted_request
          FlowChat::Config.logger&.info "FlowChat::Middleware::Pagination :: Intercepted to handle pagination"
          start, finish, has_more = calculate_offsets
          type = (pagination_state["type"].to_sym == :terminal && !has_more) ? :terminal : :prompt
          prompt = pagination_state["prompt"][start..finish].strip + build_pagination_options(type, has_more)
          set_pagination_state(current_page, start, finish)

          [type, prompt]
        end

        def maybe_paginate(type, prompt)
          if prompt.length > FlowChat::Config.ussd.pagination_page_size
            original_prompt = prompt
            FlowChat::Config.logger&.info "FlowChat::Middleware::Pagination :: Response length (#{prompt.length}) exceeds page size (#{FlowChat::Config.ussd.pagination_page_size}). Paginating."
            prompt = prompt[0..single_option_slice_size]
            # Ensure we do not cut words and options off in the middle.
            current_pagebreak = prompt[single_option_slice_size + 1].blank? ? single_option_slice_size : prompt.rindex("\n") || prompt.rindex(" ") || single_option_slice_size
            set_pagination_state(1, 0, current_pagebreak, original_prompt, type)
            prompt = prompt[0..current_pagebreak].strip + "\n\n" + next_option
            type = :prompt
          end
          [type, prompt]
        end

        def calculate_offsets
          page = current_page
          offset = pagination_state["offsets"][page.to_s]
          if offset.present?
            FlowChat::Config.logger&.debug "FlowChat::Middleware::Pagination :: Reusing cached offset for page: #{page}"
            start = offset["start"]
            finish = offset["finish"]
            has_more = pagination_state["prompt"].length > finish
          else
            FlowChat::Config.logger&.debug "FlowChat::Middleware::Pagination :: Calculating offset for page: #{page}"
            # We are guaranteed a previous offset because it was set in maybe_paginate
            previous_page = page - 1
            previous_offset = pagination_state["offsets"][previous_page.to_s]
            start = previous_offset["finish"] + 1
            has_more, len = (pagination_state["prompt"].length > start + single_option_slice_size) ? [true, dual_options_slice_size] : [false, single_option_slice_size]
            finish = start + len
            if start > pagination_state["prompt"].length
              FlowChat::Config.logger&.debug "FlowChat::Middleware::Pagination :: No content exists for page: #{page}. Reverting to page: #{page - 1}"
              page -= 1
              has_more = false
              start = previous_offset["start"]
              finish = previous_offset["finish"]
            else
              prompt = pagination_state["prompt"][start..finish]
              current_pagebreak = pagination_state["prompt"][finish + 1].blank? ? len : prompt.rindex("\n") || prompt.rindex(" ") || len
              finish = start + current_pagebreak
            end
          end
          [start, finish, has_more]
        end

        def build_pagination_options(type, has_more)
          options_str = ""
          has_less = current_page > 1
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
          end
          @single_option_slice_size
        end

        def dual_options_slice_size
          unless @dual_options_slice_size.present?
            # To display both back and next options
            # We accomodate the 3 newlines and both of the options
            @dual_options_slice_size = FlowChat::Config.ussd.pagination_page_size - 3 - [next_option.length, back_option.length].sum - 1
          end
          @dual_options_slice_size
        end

        def current_page
          page = pagination_state["page"]
          if @context.input == FlowChat::Config.ussd.pagination_back_option
            page -= 1
          elsif @context.input == FlowChat::Config.ussd.pagination_next_option
            page += 1
          end
          [page, 1].max
        end

        def pagination_state
          @pagination_state ||= @context.session.get("ussd.pagination") || {}
        end

        def set_pagination_state(page, offset_start, offset_finish, prompt = nil, type = nil)
          offsets = pagination_state["offsets"] || {}
          offsets[page] = {start: offset_start, finish: offset_finish}
          prompt ||= pagination_state["prompt"]
          type ||= pagination_state["type"]
          @pagination_state = {
            "page" => page,
            "offsets" => offsets,
            "prompt" => prompt,
            "type" => type
          }
          @session.set "ussd.pagination", @pagination_state
        end
      end
    end
  end
end
