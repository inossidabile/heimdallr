module Heimdallr
  # This is an internal class which runs security validations when {Proxy::Record#save}
  # and {Proxy::Record#save!} are invoked. +ActiveRecord::Base#save+ (and +save!+) clears
  # the +errors+ object internally, so this hack is required to avoid monkey-patching it.
  class Validator < ActiveModel::Validator
    # Run the +record.heimdallr_validators+ on the current record, if any.
    def validate(record)
      if record.heimdallr_validators
        record.heimdallr_validators.each do |validator|
          validator.validate(record)
        end
      end
    end
  end
end