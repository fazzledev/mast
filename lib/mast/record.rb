module Mast
  # The part of ActiveRecord the models use: a table named after the class,
  # attribute readers, find/find_by/where/create, update, and created_at and
  # updated_at kept up to date. Queries are SQL with ? binds; there is no
  # relation to chain, just arrays of records.
  class Record
    class RecordNotFound < StandardError; end

    class << self
      # Attempt -> attempts, PassageView -> passage_views.
      def table_name
        @table_name ||= "#{name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase}s"
      end

      # A column name, or a list of them for a composite key.
      def primary_key(*columns)
        @primary_key = columns.map(&:to_s) unless columns.empty?
        @primary_key || ["id"]
      end

      def db = Mast.db

      # Read once per process, so a column never set still reads as nil.
      def column_names
        @column_names ||= db.execute("SELECT name FROM pragma_table_info(?)", [table_name]).map { |c| c["name"] }
      end

      def where(clause = "1", *binds, order: nil, limit: nil)
        sql = "SELECT * FROM #{table_name} WHERE #{clause}"
        sql += " ORDER BY #{order}" if order
        sql += " LIMIT #{Integer(limit)}" if limit
        find_by_sql(sql, binds)
      end

      def find_by(conditions)
        where(conditions.keys.map { |k| "#{k} = ?" }.join(" AND "), *conditions.values, limit: 1).first
      end

      def find(*key)
        find_by(primary_key.zip(key).to_h) or raise RecordNotFound, "#{name} #{key.join(", ")}"
      end

      def find_by_sql(sql, binds = [])
        db.execute(sql, binds).map { |row| new(row, persisted: true) }
      end

      def create(attributes = {}, replace: false, **more)
        new(attributes, **more).tap { |record| record.save(replace: replace) }
      end
    end

    attr_reader :attributes

    # Attributes as a hash, or as keywords: new(site: "youtube").
    def initialize(attributes = {}, persisted: false, **more)
      @attributes = attributes.merge(more).transform_keys(&:to_s)
      @persisted = persisted
    end

    def persisted? = @persisted

    def [](name) = @attributes[name.to_s]

    # INSERT, or with replace: INSERT OR REPLACE.
    def save(replace: false)
      now = Time.now.to_f
      @attributes["created_at"] ||= now
      @attributes["updated_at"] ||= now
      columns = @attributes.keys
      self.class.db.execute(
        "INSERT #{replace ? "OR REPLACE " : ""}INTO #{self.class.table_name} (#{columns.join(", ")}) " \
        "VALUES (#{(["?"] * columns.length).join(", ")})",
        @attributes.values,
      )
      @persisted = true
      self
    end

    def update(changes)
      changes = changes.transform_keys(&:to_s).merge("updated_at" => Time.now.to_f)
      key = self.class.primary_key
      self.class.db.execute(
        "UPDATE #{self.class.table_name} SET #{changes.keys.map { |c| "#{c} = ?" }.join(", ")} " \
        "WHERE #{key.map { |k| "#{k} = ?" }.join(" AND ")}",
        changes.values + key.map { |k| @attributes[k] },
      )
      @attributes.merge!(changes)
      self
    end

    def ==(other)
      other.class == self.class && self.class.primary_key.all? { |k| other[k] == self[k] }
    end

    def respond_to_missing?(name, include_private = false)
      attribute?(name) || super
    end

    # Attribute readers for the table's columns, plus whatever extra columns a
    # query selected.
    def method_missing(name, *args)
      return @attributes[name.to_s] if args.empty? && attribute?(name)
      super
    end

    private

    def attribute?(name) = @attributes.key?(name.to_s) || self.class.column_names.include?(name.to_s)
  end
end
