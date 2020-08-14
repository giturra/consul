module Verification
  extend ActiveSupport::Concern

  included do
    scope :residence_verified, -> { where.not(residence_verified_at: nil) }
    scope :level_three_verified, -> { where.not(verified_at: nil) }
    scope :level_two_verified, -> { where("users.level_two_verified_at IS NOT NULL OR (users.residence_verified_at IS NOT NULL) AND verified_at IS NULL") }
    scope :level_two_or_three_verified, -> { where("users.verified_at IS NOT NULL OR users.level_two_verified_at IS NOT NULL OR (users.residence_verified_at IS NOT NULL)") }
    scope :unverified, -> { where("users.verified_at IS NULL AND (users.level_two_verified_at IS NULL AND (users.residence_verified_at IS NULL OR users.confirmed_phone IS NULL))") }
    scope :incomplete_verification, -> { where("(users.residence_verified_at IS NULL AND users.failed_census_calls_count > ?) OR (users.residence_verified_at IS NOT NULL)", 0) }
  end

  def skip_verification?
    Setting["feature.user.skip_verification"].present?
  end

  def verification_email_sent?
    return true if skip_verification?

    email_verification_token.present?
  end

  def verification_sms_sent?
    true
  end

  def verification_letter_sent?
    true
  end

  def residence_verified?
    return true if skip_verification?

    residence_verified_at.present?
  end

  def sms_verified?
    true
  end

  def level_two_verified?
    return true if skip_verification?

    level_two_verified_at.present? || (residence_verified? && sms_verified?)
  end

  def level_three_verified?
    return true if skip_verification?

    verified_at.present?
  end

  def level_two_or_three_verified?
    level_two_verified? || level_three_verified?
  end

  def unverified?
    !level_two_or_three_verified?
  end

  def failed_residence_verification?
    !residence_verified? && !failed_census_calls.empty?
  end

  def no_phone_available?
  end

  def user_type
    if level_three_verified?
      :level_3_user
    elsif level_two_verified?
      :level_2_user
    else
      :level_1_user
    end
  end

  def sms_code_not_confirmed?
  end
end
