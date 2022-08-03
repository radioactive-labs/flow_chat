module UssdEngine
  module Controller
    module Forkable
      protected

      def self.included(base)
        base.stores :forkable_stack
      end

      def create_fork(source_screen, forked_screen, destination_screen, input = nil)
        Config.logger&.debug "UssdEngine::Controller::Forkable :: Creating fork: #{source_screen} -> #{forked_screen} -> #{destination_screen}"

        self.forkable_stack ||= []
        self.forkable_stack.append({
          source: source_screen,
          fork: forked_screen,
          destination: destination_screen,
        })

        display forked_screen, input
      end

      def refork(forked_screen, destination_screen, input = nil)
        raise "You cannot refork outside of a fork" unless forkable_stack.size.positive?
        Config.logger&.debug "UssdEngine::Controller::Forkable :: Creating refork:  #{forked_screen} -> #{destination_screen}"

        create_fork :forkable_refork, forked_screen, destination_screen, input
      end

      def abort_fork(input = nil)
        branch = self.forkable_stack.pop
        while branch[:source].to_sym == :forkable_refork
          branch = self.forkable_stack.pop
        end
        Config.logger&.debug "UssdEngine::Controller::Forkable :: Aborting fork: #{branch[:fork]} -> #{branch[:source]} #{self.forkable_stack}"
        Config.logger&.debug "#{forkable_stack}"
        display branch[:source], input
      end

      def join_fork(input = nil)
        branch = self.forkable_stack.pop
        Config.logger&.debug "UssdEngine::Controller::Forkable :: Joining fork: #{branch[:fork]} -> #{branch[:destination]}"
        Config.logger&.debug "#{forkable_stack}"
        display branch[:destination], input
      end
    end
  end
end
