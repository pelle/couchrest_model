module CouchRest
  module Model
    module Views
      extend ActiveSupport::Concern

      module ClassMethods
        # Define a CouchDB view. The name of the view will be the concatenation
        # of <tt>by</tt> and the keys joined by <tt>_and_</tt>
        #
        # ==== Example views:
        #
        #   class Post
        #     # view with default options
        #     # query with Post.by_date
        #     view_by :date, :descending => true
        #
        #     # view with compound sort-keys
        #     # query with Post.by_user_id_and_date
        #     view_by :user_id, :date
        #
        #     # view with custom map/reduce functions
        #     # query with Post.by_tags :reduce => true
        #     view_by :tags,
        #       :map =>
        #         "function(doc) {
        #           if (doc['model'] == 'Post' && doc.tags) {
        #             doc.tags.forEach(function(tag){
        #               emit(doc.tag, 1);
        #             });
        #           }
        #         }",
        #       :reduce =>
        #         "function(keys, values, rereduce) {
        #           return sum(values);
        #         }"
        #   end
        #
        # <tt>view_by :date</tt> will create a view defined by this Javascript
        # function:
        #
        #   function(doc) {
        #     if (doc['model'] == 'Post' && doc.date) {
        #       emit(doc.date, null);
        #     }
        #   }
        #
        # It can be queried by calling <tt>Post.by_date</tt> which accepts all
        # valid options for CouchRest::Database#view. In addition, calling with
        # the <tt>:raw => true</tt> option will return the view rows
        # themselves. By default <tt>Post.by_date</tt> will return the
        # documents included in the generated view.
        #
        # Calling with :database => [instance of CouchRest::Database] will
        # send the query to a specific database, otherwise it will go to
        # the model's default database (use_database)
        #
        # CouchRest::Database#view options can be applied at view definition
        # time as defaults, and they will be curried and used at view query
        # time. Or they can be overridden at query time.
        #
        # Custom views can be queried with <tt>:reduce => true</tt> to return
        # reduce results. The default for custom views is to query with
        # <tt>:reduce => false</tt>.
        #
        # Views are generated (on a per-model basis) lazily on first-access.
        # This means that if you are deploying changes to a view, the views for
        # that model won't be available until generation is complete. This can
        # take some time with large databases. Strategies are in the works.
        #
        # To understand the capabilities of this view system more completely,
        # it is recommended that you read the RSpec file at
        # <tt>spec/couchrest/more/extended_doc_spec.rb</tt>.

        def view_by(*keys)
          opts = keys.pop if keys.last.is_a?(Hash)
          opts ||= {}
          ducktype = opts.delete(:ducktype)
          unless ducktype || opts[:map]
            opts[:guards] ||= []
            opts[:guards].push "(doc['#{model_type_key}'] == '#{self.to_s}')"
          end
          keys.push opts
          design_doc.view_by(*keys)
        end

        # returns stored defaults if there is a view named this in the design doc
        def has_view?(name)
          design_doc && design_doc.has_view?(name)
        end

        # Check if the view can be reduced by checking to see if it has a
        # reduce function.
        def can_reduce_view?(name)
          design_doc && design_doc.can_reduce_view?(name)
        end

        # Dispatches to any named view.
        def view(name, query={}, &block)
          query = query.dup # Modifications made on copy!
          db = query.delete(:database) || database
          query[:raw] = true if query[:reduce]
          raw = query.delete(:raw)
          save_design_doc(db)
          fetch_view_with_docs(db, name, query, raw, &block)
        end

        # Find the first entry in the view. If the second parameter is a string
        # it will be used as the key for the request, for example:
        #
        #     Course.first_from_view('by_teacher', 'Fred')
        #
        # More advanced requests can be performed by providing a hash:
        #
        #     Course.first_from_view('by_teacher', :startkey => 'bbb', :endkey => 'eee')
        #
        def first_from_view(name, *args)
          query = {:limit => 1}
          case args.first
          when String, Array
            query.update(args[1]) unless args[1].nil?
            query[:key] = args.first
          when Hash
            query.update(args.first)
          end
          view(name, query).first
        end

        private

        def fetch_view_with_docs(db, name, opts, raw=false, &block)
          if raw || (opts.has_key?(:include_docs) && opts[:include_docs] == false)
            fetch_view(db, name, opts, &block)
          else
            opts = opts.merge(:include_docs => true)
            view = fetch_view db, name, opts, &block
            view['rows'].collect{|r| build_from_database(r['doc'])} if view['rows']
          end
        end

        def fetch_view(db, view_name, opts, &block)
          raise "A view needs a database to operate on (specify :database option, or use_database in the #{self.class} class)" unless db
          design_doc.view_on(db, view_name, opts, &block)
        end
      end # module ClassMethods

    end
  end
end
