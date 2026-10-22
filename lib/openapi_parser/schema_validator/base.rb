class OpenAPIParser::SchemaValidator
  class Base
    def initialize(validatable, coerce_value)
      @validatable = validatable
      @coerce_value = coerce_value
    end

    attr_reader :validatable

    # need override
    def coerce_and_validate(_value, _schema, **_keyword_args)
      raise 'need implement'
    end

    def validate_discriminator_schema(discriminator, value, parent_discriminator_schemas: [])
      property_name = discriminator.property_name
      if property_name && value.key?(property_name)
        mapping_key = value[property_name]
        explicit_target = discriminator.mapping&.[](mapping_key)

        # it's allowed to have discriminator without mapping, then we need to lookup discriminator.property_name
        # but the format is not the full path, just model name in the components
        mapping_target = explicit_target || "#/components/schemas/#{mapping_key}"

        # Find object does O(n) search at worst, then caches the result, so this is ok for repeated search
        resolved_schema = discriminator.root.find_object(mapping_target)
      end

      # defaultMapping (3.2) applies when the property is absent or its value
      # has neither an explicit mapping nor an implicit schema match
      if resolved_schema.nil? && explicit_target.nil? && (default_target = default_mapping_target(discriminator))
        mapping_target = default_target
        resolved_schema = discriminator.root.find_object(default_target)
      end

      unless mapping_target
        return [nil, OpenAPIParser::NotExistDiscriminatorPropertyName.new(discriminator.property_name, value, discriminator.object_reference)]
      end

      unless resolved_schema
        return [nil, OpenAPIParser::NotExistDiscriminatorMappedSchema.new(mapping_target, discriminator.object_reference)]
      end
      validatable.validate_schema(
        value,
        resolved_schema,
        **{discriminator_property_name: discriminator.property_name, parent_discriminator_schemas: parent_discriminator_schemas}
      )
    end

    private

      # defaultMapping holds a schema name or a URI reference; only
      # same-document references resolve. Ignored where 3.2 behavior doesn't apply
      def default_mapping_target(discriminator)
        return nil unless discriminator.root.use_3_2_features?

        target = discriminator.default_mapping
        return nil unless target.is_a?(String)

        target.start_with?('#') || target.include?('/') ? target : "#/components/schemas/#{target}"
      end
  end
end
