# frozen_string_literal: true

require 'rainbow'

module RuboCop
  module AST
    class NodePattern
      class Compiler
        # Variant of the Compiler with tracing information for nodes
        class Debug < Compiler
          # Compiled node pattern requires a named parameter `trace`,
          # which should be an instance of this class
          class Trace
            def initialize
              @visit = {}
            end

            def enter(node_id)
              @visit[node_id] = false
              true
            end

            def success(node_id)
              @visit[node_id] = true
            end

            # return nil (not visited), false (not matched) or true (matched)
            def matched?(node_id)
              @visit[node_id]
            end
          end

          attr_reader :node_ids

          # @api private
          class Colorizer
            # Result of a NodePattern run against a particular AST
            # Consider constructor is private
            Result = Struct.new(:colorizer, :trace, :returned) do # rubocop:disable Metrics/BlockLength
              # @return [String] a Rainbow colorized version of ruby
              def colorize
                ast.loc.expression.source_buffer.source.chars.map.with_index do |char, i|
                  Rainbow(char).color((color_map[i] || COLORS[:not_visitable]))
                end.join
              end

              # @return [Hash] a map for {character_position => color}
              def color_map
                @color_map ||=
                  match_map
                  .map { |node, matched| color_map_for(node, matched) }
                  .inject(:merge)
              end

              # @return [Hash] a map for {node => matched?}, depth-first
              def match_map
                @match_map ||=
                  ast
                  .each_descendant
                  .to_a
                  .prepend(ast)
                  .to_h { |node| [node, matched?(node)] }
              end

              def matched?(node)
                id = colorizer.compiler.node_ids.fetch(node) { return :not_visitable }
                trace.matched?(id)
              end

              private

              COLORS = {
                not_visitable: :lightseagreen,
                nil => :yellow,
                false => :red,
                true => :green
              }.freeze

              def color_map_for(node, matched = matched?(node))
                return {} unless (range = node.loc&.expression)

                color = COLORS.fetch(matched)
                range.to_a.to_h { |char| [char, color] }
              end

              def ast
                colorizer.node_pattern.ast
              end
            end

            attr_reader :pattern, :compiler, :node_pattern

            def initialize(pattern)
              @pattern = pattern
              @compiler = ::RuboCop::AST::NodePattern::Compiler::Debug.new
              @node_pattern = ::RuboCop::AST::NodePattern.new(pattern, compiler: @compiler)
            end

            # @return [Node] the Ruby AST
            def test(ruby)
              ruby = ruby_ast(ruby) if ruby.is_a?(String)
              trace = Trace.new
              returned = @node_pattern.as_lambda.call(ruby, trace: trace)
              Result.new(self, trace, returned)
            end

            private

            def ruby_ast(ruby)
              buffer = ::Parser::Source::Buffer.new('(ruby)', source: ruby)
              ruby_parser.parse(buffer)
            end

            def ruby_parser
              require 'parser/current'
              builder = ::RuboCop::AST::Builder.new
              ::Parser::CurrentRuby.new(builder)
            end
          end

          def initialize
            super
            @node_ids = Hash.new { |h, k| h[k] = h.size }.compare_by_identity
          end

          def named_parameters
            super << :trace
          end

          def parser
            Parser::WithMeta
          end

          # @api private
          module InstrumentationSubcompiler
            def do_compile
              "#{tracer(:enter)} && #{super} && #{tracer(:success)}"
            end

            private

            def tracer(kind)
              id = compiler.node_ids[node]
              "trace.#{kind}(#{id})"
            end
          end

          # @api private
          class NodePatternSubcompiler < Compiler::NodePatternSubcompiler
            include InstrumentationSubcompiler
          end

          # @api private
          class SequenceSubcompiler < Compiler::SequenceSubcompiler
            include InstrumentationSubcompiler
          end
        end
      end
    end
  end
end
