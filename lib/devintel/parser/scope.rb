# frozen_string_literal: true

module DevIntel
  module Parser
    # Tracks where in the source the extractor currently is.
    #
    # Three things change as the walk descends and they change together: the
    # namespace a name is qualified by, which definition owns the references
    # found here, and whether `def` means an instance or a singleton method.
    # Keeping them as one object makes it impossible to push one and forget
    # another.
    class Scope
      def initialize
        @namespace = []
        @owners = [nil]
        @singletons = [false]
      end

      # "Billing::Invoice", or "" at the top level.
      def namespace
        @namespace.join("::")
      end

      # Index of the definition that owns references found here.
      def owner
        @owners.last
      end

      def singleton?
        @singletons.last
      end

      def qualify(name)
        (@namespace + [name]).join("::")
      end

      # Entering a class or module body: all three change.
      def descend(path, owner_index)
        @namespace.push(path)
        @owners.push(owner_index)
        @singletons.push(false)
        yield
      ensure
        @singletons.pop
        @owners.pop
        @namespace.pop
      end

      # Entering a method body: references belong to the method, but the
      # namespace is unchanged.
      def own(owner_index)
        @owners.push(owner_index)
        yield
      ensure
        @owners.pop
      end

      # Entering `class << self`.
      def singleton
        @singletons.push(true)
        yield
      ensure
        @singletons.pop
      end
    end
  end
end
