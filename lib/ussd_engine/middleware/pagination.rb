module UssdEngine
  module Middleware
    class Pagination
      def initialize(app)
        @app = app
      end

      def call(env)
        @env = env
        request = Rack::Request.new(env)
        @session = request.session

        if intercept?
          @env["ussd_engine.response"] = handle_intercepted_request
          [200, {}, [""]]
        else
          @session["ussd_engine.pagination"] = nil
          res = @app.call(env)

          if @env["ussd_engine.response"].present?
            @env["ussd_engine.response"] = maybe_paginate @env["ussd_engine.response"]
          end

          res
        end
      end

      private

      def intercept?
        pagination_state.present? &&
          (pagination_state[:type].to_sym == :terminal ||
           ([Config.pagination_next_option, Config.pagination_back_option].include? @env["ussd_engine.request"][:input]))
      end

      def handle_intercepted_request
        Config.logger&.info "UssdEngine::Middleware::Pagination :: Intercepted to handle pagination"
        start, finish, has_more = calculate_offsets
        type = pagination_state[:type].to_sym == :terminal && !has_more ? :terminal : :prompt
        body = pagination_state[:body][start..finish].strip + build_pagination_options(type, has_more)
        set_pagination_state(current_page, start, finish)

        { body: body, type: type }
      end

      def maybe_paginate(response)
        if response[:body].length > Config.pagination_page_size
          Config.logger&.info "UssdEngine::Middleware::Pagination :: Response length (#{response[:body].length}) exceeds page size (#{Config.pagination_page_size}). Paginating."
          body = response[:body][0..single_option_slice_size]
          # Ensure we do not cut words and options off in the middle.
          current_pagebreak = response[:body][single_option_slice_size + 1].blank? ? single_option_slice_size : body.rindex("\n") || body.rindex(" ") || single_option_slice_size
          set_pagination_state(1, 0, current_pagebreak, response[:body], response[:type])
          response[:body] = body[0..current_pagebreak].strip + "\n\n" + next_option
          response[:type] = :prompt
        end
        response
      end

      def calculate_offsets
        page = current_page
        offset = pagination_state[:offsets][page]
        if offset.present?
          Config.logger&.debug "UssdEngine::Middleware::Pagination :: Reusing cached offset for page: #{page}"
          start = offset[:start]
          finish = offset[:finish]
          has_more = pagination_state[:body].length > finish
        else
          Config.logger&.debug "UssdEngine::Middleware::Pagination :: Calculating offset for page: #{page}"
          # We are guaranteed a previous offset because it was set in maybe_paginate
          previous_offset = pagination_state[:offsets][page - 1]
          start = previous_offset[:finish] + 1
          has_more, len = pagination_state[:body].length > start + single_option_slice_size ? [true, dual_options_slice_size] : [false, single_option_slice_size]
          finish = start + len
          if start > pagination_state[:body].length
            Config.logger&.debug "UssdEngine::Middleware::Pagination :: No content exists for page: #{page}. Reverting to page: #{page - 1}"
            page -= 1
            has_more = false
            start = previous_offset[:start]
            finish = previous_offset[:finish]
          else
            body = pagination_state[:body][start..finish]
            current_pagebreak = pagination_state[:body][finish + 1].blank? ? len : body.rindex("\n") || body.rindex(" ") || len
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
        "#{Config.pagination_next_option} #{Config.pagination_next_text}"
      end

      def back_option
        "#{Config.pagination_back_option} #{Config.pagination_back_text}"
      end

      def single_option_slice_size
        unless @single_option_slice_size.present?
          # To display a single back or next option
          # We accomodate the 2 newlines and the longest of the options
          # We subtract an additional 1 to normalize it for slicing
          @single_option_slice_size = Config.pagination_page_size - 2 - [next_option.length, back_option.length].max - 1
        end
        @single_option_slice_size
      end

      def dual_options_slice_size
        unless @dual_options_slice_size.present?
          # To display both back and next options
          # We accomodate the 3 newlines and both of the options
          @dual_options_slice_size = Config.pagination_page_size - 3 - [next_option.length, back_option.length].sum - 1
        end
        @dual_options_slice_size
      end

      def current_page
        current_page = pagination_state[:page]
        if @env["ussd_engine.request"][:input] == Config.pagination_back_option
          current_page -= 1
        elsif @env["ussd_engine.request"][:input] == Config.pagination_next_option
          current_page += 1
        end
        [current_page, 1].max
      end

      def pagination_state
        @session["ussd_engine.pagination"] || {}
      end

      def set_pagination_state(page, offset_start, offset_finish, body = nil, type = nil)
        offsets = pagination_state[:offsets] || {}
        offsets[page] = { start: offset_start, finish: offset_finish }
        @session["ussd_engine.pagination"] = {
          page: page,
          offsets: offsets,
          body: body || pagination_state[:body],
          type: type || pagination_state[:type],
        }
      end
    end
  end
end
