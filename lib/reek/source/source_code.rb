# frozen_string_literal: true

require_relative '../cli/silencer'
Reek::CLI::Silencer.silently do
  require 'parser/ruby23'
end
require_relative '../tree_dresser'
require_relative '../ast/node'
require_relative '../errors/parse_error'

# Opt in to new way of representing lambdas
Parser::Builders::Default.emit_lambda = true

module Reek
  module Source
    #
    # A +Source+ object represents a chunk of Ruby source code.
    #
    class SourceCode
      IO_IDENTIFIER     = 'STDIN'.freeze
      STRING_IDENTIFIER = 'string'.freeze

      attr_reader :origin

      # Initializer.
      #
      # code   - Ruby code as String
      # origin - 'STDIN', 'string' or a filepath as String
      # parser - the parser to use for generating AST's out of the given source
      def initialize(code:, origin:, parser: Parser::Ruby23)
        @source = code
        @origin = origin
        @parser = parser
      end

      # Initializes an instance of SourceCode given a source.
      # This source can come via 4 different ways:
      # - from Files or Pathnames a la `reek lib/reek/`
      # - from IO (STDIN) a la `echo "class Foo; end" | reek`
      # - from String via our rspec matchers a la `expect("class Foo; end").to reek`
      #
      # @param source [File|IO|String] - the given source
      #
      # @return an instance of SourceCode
      # :reek:DuplicateMethodCall: { max_calls: 2 }
      def self.from(source)
        case source
        when File     then new(code: source.read,           origin: source.path)
        when IO       then new(code: source.readlines.join, origin: IO_IDENTIFIER)
        when Pathname then new(code: source.read,           origin: source.to_s)
        when String   then new(code: source,                origin: STRING_IDENTIFIER)
        end
      end

      # Parses the given source into an AST and associates the source code comments with it.
      # This AST is then traversed by a TreeDresser which adorns the nodes in the AST
      # with our SexpExtensions.
      # Finally this AST is returned where each node is an anonymous subclass of Reek::AST::Node
      #
      # Important to note is that Reek will not fail on unparseable files but rather print out
      # a warning and then just continue.
      #
      # Given this @source:
      #
      #   # comment about C
      #   class C
      #     def m
      #       puts 'nada'
      #     end
      #   end
      #
      # this method would return something that looks like
      #
      #   (class
      #     (const nil :C) nil
      #     (def :m
      #       (args)
      #       (send nil :puts
      #         (str "nada"))))
      #
      # where each node is possibly adorned with our SexpExtensions (see ast/ast_node_class_map
      # and ast/sexp_extensions for details).
      #
      #  @return [Anonymous subclass of Reek::AST::Node] the AST presentation
      #          for the given source
      def syntax_tree
        @syntax_tree ||=
          begin
            begin
              ast, comments = parser.parse_with_comments(source, origin)
            rescue Racc::ParseError, Parser::SyntaxError => error
              raise Errors::ParseError, origin: origin, original_exception: error
            end

            # See https://whitequark.github.io/parser/Parser/Source/Comment/Associator.html
            comment_map = Parser::Source::Comment.associate(ast, comments) if ast
            TreeDresser.new.dress(ast, comment_map)
          end
      end

      private

      attr_reader :parser, :source
    end
  end
end
