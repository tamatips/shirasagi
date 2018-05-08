class Workflow::PagesController < ApplicationController
  include Cms::BaseFilter
  include Cms::CrudFilter

  before_action :set_item, only: %i[request_update restart_update approve_update pull_up_update remand_update branch_create]

  private

  def set_model
    @model = Cms::Page
  end

  def set_item
    @item = @model.find(params[:id]).becomes_with_route
    @item.attributes = fix_params
    @item.try(:allow_other_user_files)
  end

  def fix_params
    { cur_user: @cur_user, cur_site: @cur_site, cur_node: false }
  end

  def request_approval
    current_level = @item.workflow_current_level
    current_workflow_approvers = @item.workflow_pull_up_approvers_at(current_level)
    Workflow::Mailer.send_request_mails(
      f_uid: @cur_user._id, t_uids: current_workflow_approvers.map { |approver| approver[:user_id] },
      site: @cur_site, page: @item,
      url: params[:url], comment: params[:workflow_comment]
    )

    @item.set_workflow_approver_state_to_request
    @item.save
  end

  def workflow_alert
    email_blank_users = []
    target_user = nil
    email_blank_users.push(@cur_user.name) if @cur_user.email.blank?
    if params[:workflow_approvers].present?
      params[:workflow_approvers].each do |workflow_approver|
        element = workflow_approver.split(",")
        target_user = SS::User.find(element[1]) rescue nil
        if target_user
          email_blank_users.push(target_user.name) if target_user.email.blank?
        end
      end
    else
      current_level = @item.workflow_current_level
      current_workflow_approvers = @item.workflow_approvers_at(current_level)
      current_workflow_approvers.each do |workflow_approver|
        target_user = SS::User.find(workflow_approver[:user_id]) rescue nil
        if target_user
          email_blank_users.push(target_user.name) if target_user.email.blank?
        end
      end
      target_user = nil
      target_user_id = @item.workflow_user_id || @cur_user._id
      target_user = SS::User.find(target_user_id) rescue nil
      if target_user
        email_blank_users.push(target_user.name) if target_user.email.blank?
      end
    end
    email_blank_users.uniq!
    email_blank_users.sort!
    return nil if email_blank_users.blank?
    message = t("errors.messages.user_email_blank")
    email_blank_users.each do |email_blank_user|
      message += "\n#{email_blank_user}"
    end
    message
  end

  public

  def request_update
    raise "403" unless @item.allowed?(:edit, @cur_user)

    if params[:forced_update_option] == "false"
      if message = workflow_alert
        render json: { workflow_alert: message }
        return
      end
    end

    @item.approved = nil
    @item.workflow_user_id = @cur_user.id
    @item.workflow_state = @model::WORKFLOW_STATE_REQUEST
    @item.workflow_comment = params[:workflow_comment]
    @item.workflow_pull_up = params[:workflow_pull_up].present? ? params[:workflow_pull_up] : 'disabled'
    @item.workflow_on_remand = params[:workflow_on_remand]
    @item.workflow_approvers = params[:workflow_approvers]
    @item.workflow_required_counts = params[:workflow_required_counts]

    if @item.save
      request_approval
      render json: { workflow_state: @item.workflow_state }
    else
      render json: @item.errors.full_messages, status: :unprocessable_entity
    end
  end

  def restart_update
    raise "403" unless @item.allowed?(:edit, @cur_user)

    @item.approved = nil
    @item.workflow_user_id = @cur_user.id
    @item.workflow_state = @model::WORKFLOW_STATE_REQUEST
    @item.workflow_comment = params[:workflow_comment]
    copy = @item.workflow_approvers.to_a
    copy.each do |approver|
      approver[:state] = @model::WORKFLOW_STATE_PENDING
      approver[:comment] = ''
    end
    @item.workflow_approvers = Workflow::Extensions::WorkflowApprovers.new(copy)

    if @item.save
      request_approval
      render json: { workflow_state: @item.workflow_state }
    else
      render json: @item.errors.full_messages, status: :unprocessable_entity
    end
  end

  def approve_update
    raise "403" unless @item.allowed?(:approve, @cur_user)

    if params[:forced_update_option] == "false"
      if message = workflow_alert
        render json: { workflow_alert: message }
        return
      end
    end

    save_level = @item.workflow_current_level
    if params[:action] == 'pull_up_update'
      @item.pull_up_workflow_approver_state(@cur_user, @model::WORKFLOW_STATE_APPROVE, params[:remand_comment])
    else
      @item.update_current_workflow_approver_state(@cur_user, @model::WORKFLOW_STATE_APPROVE, params[:remand_comment])
    end

    if @item.finish_workflow?
      @item.approved = Time.zone.now
      @item.workflow_state = @model::WORKFLOW_STATE_APPROVE
      @item.state = "public"

      if @item.respond_to?(:release_date)
        if @item.release_date
          @item.state = "ready"
        else
          @item.release_date = nil
        end
      end
    end

    if !@item.save
      render json: @item.errors.full_messages, status: :unprocessable_entity
      return
    end

    current_level = @item.workflow_current_level
    if save_level != current_level
      # escalate workflow
      request_approval
    end

    if @item.workflow_state == @model::WORKFLOW_STATE_APPROVE
      # finished workflow
      url = params[:url].to_s
      url.sub!(/#{@item.id}$/, @item.master.id.to_s) if @item.try(:branch?) && @item.state == "public"
      Workflow::Mailer.send_approve_mails(
        f_uid: @cur_user._id, t_uids: [ @item.workflow_user_id ],
        site: @cur_site, page: @item,
        url: url, comment: params[:remand_comment]
      )

      @item.delete if @item.try(:branch?) && @item.state == "public"
    end

    render json: { workflow_state: @item.workflow_state }
  end

  alias pull_up_update approve_update

  def remand_update
    raise "403" unless @item.allowed?(:approve, @cur_user)

    if params[:forced_update_option] == "false"
      if message = workflow_alert
        render json: { workflow_alert: message }
        return
      end
    end

    workflow_level = @item.workflow_current_level
    @item.update_current_workflow_approver_state(@cur_user, @model::WORKFLOW_STATE_REMAND, params[:remand_comment])
    if @item.workflow_back_to_init?
      @item.workflow_state = @model::WORKFLOW_STATE_REMAND
    elsif workflow_level <= 1
      @item.workflow_state = @model::WORKFLOW_STATE_REMAND
    else
      copy = @item.workflow_approvers.to_a
      copy.each do |approver|
        if approver[:level] == workflow_level - 1
          approver[:state] = @model::WORKFLOW_STATE_REQUEST
          approver[:comment] = ''
        end
      end
      @item.workflow_approvers = Workflow::Extensions::WorkflowApprovers.new(copy)
    end

    if !@item.save
      render json: @item.errors.full_messages, status: :unprocessable_entity
      return
    end

    begin
      recipients = []
      if @item.workflow_state == @model::WORKFLOW_STATE_REMAND
        recipients << @item.workflow_user_id
      else
        prev_level_approvers = @item.workflow_approvers_at(workflow_level - 1)
        recipients += prev_level_approvers.map { |hash| hash[:user_id] }
      end

      Workflow::Mailer.send_remand_mails(
        f_uid: @cur_user._id, t_uids: recipients,
        site: @cur_site, page: @item,
        url: params[:url], comment: params[:remand_comment]
      )
    end
    render json: { workflow_state: @item.workflow_state }
  end

  def request_cancel
    set_item
    raise "403" unless @item.allowed?(:edit, @cur_user)

    return if request.get?

    @item.approved = nil
    @item.workflow_user_id = nil
    @item.workflow_state = @model::WORKFLOW_STATE_CANCELLED

    if @item.save
      render json: { notice: t('workflow.notice.request_cancelled') }
    else
      render json: { workflow_alert: @item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def branch_create
    raise "400" if @item.branch?

    @item.cur_node = @item.parent
    if @item.branches.blank?
      copy = @item.new_clone
      copy.master = @item
      copy.save
    end

    @items = @item.branches
    render :branch, layout: "ss/ajax"
  end
end
