require 'spec_helper'

describe Gws::Workflow::FilesController, type: :feature, dbscope: :example, tmpdir: true, js: true do
  context "my group with circulation step" do
    let(:site) { gws_site }
    let(:admin) { gws_user }
    let!(:user1) do
      Gws::User.create name: "一般ユーザー1", uid: "user1", email: "user1@example.jp", in_password: "pass",
        group_ids: [ admin.groups.first.id ], gws_role_ids: [ Gws::Role.first.id ]
    end
    let!(:user2) do
      Gws::User.create name: "一般ユーザー2", uid: "user2", email: "user2@example.jp", in_password: "pass",
        group_ids: [ admin.groups.first.id ], gws_role_ids: [ Gws::Role.first.id ]
    end
    # let!(:user3) do
    #   Gws::User.create name: "一般ユーザー3", uid: "user3", email: "user3@example.jp", in_password: "pass",
    #     group_ids: [ admin.groups.first.id ], gws_role_ids: [ Gws::Role.first.id ]
    # end
    # let!(:user4) do
    #   Gws::User.create name: "一般ユーザー4", uid: "user4", email: "user4@example.jp", in_password: "pass",
    #     group_ids: [ admin.groups.first.id ], gws_role_ids: [ Gws::Role.first.id ]
    # end

    let(:route_name) { unique_id }
    let!(:route) do
      create(
        :gws_workflow_route, name: route_name, group_ids: admin.group_ids,
        approvers: [
          { "level" => 1, "user_id" => user1.id },
        ],
        required_counts: [ false, false, false, false, false ],
        approver_attachment_uses: %w(enabled disabled disabled disabled disabled),
        circulations: [
          { "level" => 1, "user_id" => user2.id },
        ],
        circulation_attachment_uses: %w(enabled disabled disabled)
      )
    end

    let(:item) { create :gws_workflow_file }
    let(:show_path) { gws_workflow_file_path(site, item, state: 'all') }

    let(:workflow_comment1) { unique_id }
    let(:approve_comment1) { unique_id }
    let(:circulation_comment2) { unique_id }
    let(:circulation_comment3) { unique_id }
    let(:circulation_comment4) { unique_id }

    it do
      #
      # admin: 申請する（承認者 1 段、1 名＋回覧者 1 段、1 名）
      #
      login_gws_user
      visit show_path

      within ".mod-workflow-request" do
        select route_name, from: "workflow_route"
        click_on I18n.t("workflow.buttons.select")

        fill_in "workflow[comment]", with: workflow_comment1
        click_on I18n.t("workflow.buttons.request")
      end
      expect(page).to have_css(".mod-workflow-view dd", text: /#{::Regexp.escape(user1.uid)}/)

      item.reload
      expect(item.workflow_user_id).to eq admin.id
      expect(item.workflow_state).to eq "request"
      expect(item.state).to eq "closed"
      expect(item.workflow_comment).to eq workflow_comment1
      expect(item.workflow_approvers.count).to eq 1
      expect(item.workflow_approvers).to \
        include({level: 1, user_id: user1.id, editable: '', state: 'request', comment: ''})
      expect(item.workflow_circulations.count).to eq 1
      expect(item.workflow_circulations).to \
        include({level: 1, user_id: user2.id, state: 'pending', comment: ''})

      expect(Sys::MailLog.count).to eq 1
      expect(Gws::Memo::Notice.count).to eq 1
      Gws::Memo::Notice.order_by(id: -1).first.tap do |memo|
        expect(memo.subject).to eq "[#{I18n.t("workflow.mail.subject.request")}]#{item.name} - #{item.site.name}"
        expect(memo.user_id).to eq admin.id
        expect(memo.member_ids).to eq [user1.id]
        expect(memo.text).to include("承認作業を行ってください。")
      end

      #
      # user1: 申請を承認する
      #
      login_user user1
      visit show_path

      within ".mod-workflow-approve" do
        fill_in "remand[comment]", with: approve_comment1
        click_on I18n.t("workflow.links.approver_file_upload")
      end
      within "#cboxLoadedContent" do
        attach_file "item[in_files][]", "#{Rails.root}/spec/fixtures/ss/logo.png"
        click_on I18n.t("ss.buttons.save")
      end
      within ".mod-workflow-approve" do
        click_on I18n.t("workflow.buttons.approve")
      end

      expect(page).to have_css(".mod-workflow-view dd", text: /#{::Regexp.escape(approve_comment1)}/)

      expect(SS::File.all.where(model: "workflow/approver_file").count).to eq 1
      file1 = SS::File.all.where(model: "workflow/approver_file").order_by(id: -1).first
      expect(file1.name).to eq "logo.png"
      expect(file1.filename).to eq "logo.png"

      item.reload
      expect(item.workflow_user_id).to eq admin.id
      expect(item.workflow_state).to eq "approve"
      expect(item.state).to eq "approve"
      expect(item.workflow_comment).to eq workflow_comment1
      expect(item.workflow_approvers.count).to eq 1
      expect(item.workflow_approvers).to \
        include({level: 1, user_id: user1.id, editable: '', state: 'approve', comment: approve_comment1, file_ids: [file1.id]})
      expect(item.workflow_circulations.count).to eq 1
      expect(item.workflow_circulations).to \
        include({level: 1, user_id: user2.id, state: 'unseen', comment: ''})

      expect(Sys::MailLog.count).to eq 2
      expect(Gws::Memo::Notice.count).to eq 3
      Gws::Memo::Notice.order_by(id: -1).second.tap do |memo|
        expect(memo.subject).to eq "[#{I18n.t("workflow.mail.subject.approve")}]#{item.name} - #{item.site.name}"
        expect(memo.user_id).to eq user1.id
        expect(memo.member_ids).to eq [admin.id]
        expect(memo.text).to include("次の申請が承認されました。")
      end
      Gws::Memo::Notice.order_by(id: -1).first.tap do |memo|
        expect(memo.subject).to eq "[#{I18n.t("workflow.mail.subject.approve")}]#{item.name} - #{item.site.name}"
        expect(memo.user_id).to eq user1.id
        expect(memo.member_ids).to eq [user2.id]
        expect(memo.text).to include("申請内容を確認してください。")
      end

      #
      # user2: 申請を確認する
      #
      login_user user2
      visit show_path

      within ".mod-workflow-approve" do
        fill_in "remand[comment]", with: circulation_comment2
        click_on I18n.t("workflow.links.approver_file_upload")
      end
      within "#cboxLoadedContent" do
        attach_file "item[in_files][]", "#{Rails.root}/spec/fixtures/ss/logo.png"
        click_on I18n.t("ss.buttons.save")
      end
      within ".mod-workflow-approve" do
        click_on I18n.t("workflow.links.set_seen")
      end

      expect(page).to have_css(".mod-workflow-view dd", text: /#{::Regexp.escape(circulation_comment2)}/)

      expect(SS::File.all.where(model: "workflow/approver_file").count).to eq 2
      file2 = SS::File.all.where(model: "workflow/approver_file").order_by(id: -1).first
      expect(file2.name).to eq "logo.png"
      expect(file2.filename).to eq "logo.png"

      item.reload
      expect(item.workflow_user_id).to eq admin.id
      expect(item.workflow_state).to eq "approve"
      expect(item.state).to eq "approve"
      expect(item.workflow_comment).to eq workflow_comment1
      expect(item.workflow_approvers.count).to eq 1
      expect(item.workflow_approvers).to \
        include({level: 1, user_id: user1.id, editable: '', state: 'approve', comment: approve_comment1, file_ids: [file1.id]})
      expect(item.workflow_circulations.count).to eq 1
      expect(item.workflow_circulations).to \
        include({level: 1, user_id: user2.id, state: 'seen', comment: circulation_comment2, file_ids: [file2.id]})

      expect(Sys::MailLog.count).to eq 2
      expect(Gws::Memo::Notice.count).to eq 4
      Gws::Memo::Notice.order_by(id: -1).first.tap do |memo|
        expect(memo.subject).to eq "[#{I18n.t("workflow.mail.subject.approve")}]#{item.name} - #{item.site.name}"
        expect(memo.user_id).to eq user2.id
        expect(memo.member_ids).to eq [admin.id]
        expect(memo.text).to include("次の申請にコメントがありました。")
      end
    end
  end
end