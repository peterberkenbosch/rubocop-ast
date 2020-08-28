# frozen_string_literal: true

module RuboCop
  module AST
    class NodePattern
      # Base for compilers
      class Compiler
        # @api private
        def do_compile
          callback(self.class.registry[node.type])
        end

        protected

        attr_reader :context, :node

        private

        def initialize(context, node = nil)
          @context = context
          @node = node
        end

        def compile(node)
          prev = @node
          @node = node
          do_compile
        ensure
          @node = prev
        end

        def callback(method)
          send(method)
        end

        @registry = Hash.new(:on_type_missing)
        class << self
          attr_reader :registry

          def method_added(method)
            @registry[Regexp.last_match(1).to_sym] = method if method =~ /^on_(.*)/
            super
          end

          def inherited(base)
            us = self
            base.class_eval { @registry = us.registry.dup }
            super
          end
        end
      end
    end
  end
end