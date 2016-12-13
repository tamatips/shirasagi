require 'spec_helper'

describe "jmaxml/trigger/quake_intensity_flashes", dbscope: :example, js: true do
  let(:site) { cms_site }
  let(:node) { create :rss_node_weather_xml, cur_site: site }
  let(:index_path) { jmaxml_trigger_bases_path(site, node) }

  it "without login" do
    visit index_path
    expect(current_path).to eq sns_login_path
  end

  it "without auth" do
    login_ss_user
    visit index_path
    expect(status_code).to eq 403
  end

  context "basic crud" do
    let!(:region) { create(:jmaxml_region_135) }
    let(:model) { Jmaxml::Trigger::QuakeIntensityFlash }
    let(:name1) { unique_id }
    let(:name2) { unique_id }

    before { login_cms_user }

    it do
      #
      # create
      #
      visit index_path
      click_on I18n.t('views.links.new')

      within 'form' do
        select model.model_name.human, from: 'item[in_type]'
        click_on I18n.t('views.button.new')
      end

      within 'form' do
        fill_in 'item[name]', with: name1
        select I18n.t('rss.options.earthquake_intensity.5+'), from: 'item[earthquake_intensity]'
        click_on I18n.t('jmaxml.apis.quake_regions.index')
      end
      within '.items' do
        click_on region.name
      end
      within 'form' do
        click_on I18n.t('views.button.save')
      end
      expect(page).to have_css('#notice', text: I18n.t('views.notice.saved'), wait: 60)

      expect(model.count).to eq 1
      model.first.tap do |trigger|
        expect(trigger.name).to eq name1
        expect(trigger.training_status).to eq 'disabled'
        expect(trigger.test_status).to eq 'disabled'
        expect(trigger.earthquake_intensity).to eq '5+'
        expect(trigger.target_region_ids.first).to eq region.id
      end

      #
      # update
      #
      visit index_path
      click_on name1
      click_on I18n.t('views.links.edit')

      within 'form' do
        fill_in 'item[name]', with: name2
        select I18n.t('rss.options.earthquake_intensity.4'), from: 'item[earthquake_intensity]'
        click_on I18n.t('views.button.save')
      end
      expect(page).to have_css('#notice', text: I18n.t('views.notice.saved'), wait: 60)

      expect(model.count).to eq 1
      model.first.tap do |trigger|
        expect(trigger.name).to eq name2
        expect(trigger.training_status).to eq 'disabled'
        expect(trigger.test_status).to eq 'disabled'
        expect(trigger.earthquake_intensity).to eq '4'
        expect(trigger.target_region_ids.first).to eq region.id
      end

      #
      # delete
      #
      visit index_path
      click_on name2
      click_on I18n.t('views.links.delete')

      within 'form' do
        click_on I18n.t('views.button.delete')
      end
      expect(page).to have_css('#notice', text: I18n.t('views.notice.saved'), wait: 60)

      expect(model.count).to eq 0
    end
  end
end
