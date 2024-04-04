module FlowChat
  module Ussd
    module Simulator
      module Controller
        def ussd_simulator
          respond_to do |format|
            format.html do
              render inline: simulator_view_template, layout: false, locals: simulator_locals
            end
          end
        end

        protected

        def show_options
          true
        end

        def default_msisdn
          "233200123456"
        end

        def default_endpoint
          "/ussd"
        end

        def default_provider
          :nalo
        end

        def simulator_view_template
          File.read simulator_view_path
        end

        def simulator_view_path
          File.join FlowChat.root.join("flow_chat", "ussd", "simulator", "views", "simulator.html.erb")
        end

        def simulator_locals
          {
            pagesize: Config.pagination_page_size,
            show_options: show_options,
            default_msisdn: default_msisdn,
            default_endpoint: default_endpoint,
            default_provider: default_provider
          }
        end
      end
    end
  end
end
