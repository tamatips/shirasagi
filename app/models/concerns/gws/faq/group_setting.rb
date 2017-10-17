module Gws::Faq::GroupSetting
  extend ActiveSupport::Concern
  extend Gws::GroupSetting

  included do
    field :faq_new_days, type: Integer
    field :faq_file_size_per_topic, type: Integer
    field :faq_file_size_per_post, type: Integer
    field :faq_browsed_delay, type: Integer
    attr_accessor :in_faq_file_size_per_topic_mb, :in_faq_file_size_per_post_mb

    permit_params :faq_new_days, :faq_browsed_delay
    permit_params :in_faq_file_size_per_topic_mb, :in_faq_file_size_per_post_mb

    before_validation :set_faq_file_size_per_topic
    before_validation :set_faq_file_size_per_post
  end

  def faq_new_days
    self[:faq_new_days].presence || 7
  end

  def faq_browsed_delay
    self[:faq_browsed_delay].presence || 2
  end

  class << self
    # Permission for navigation view
    def allowed?(action, user, opts = {})
      return true if Gws::Faq::Category.allowed?(action, user, opts)
      super
    end
  end

  private

  def set_faq_file_size_per_topic
    return if in_faq_file_size_per_topic_mb.blank?
    self.faq_file_size_per_topic = Integer(in_faq_file_size_per_topic_mb) * 1_024 * 1_024
  end

  def set_faq_file_size_per_post
    return if in_faq_file_size_per_post_mb.blank?
    self.faq_file_size_per_post = Integer(in_faq_file_size_per_post_mb) * 1_024 * 1_024
  end
end