class Cms::ContentsController < ApplicationController
  include Cms::BaseFilter

  navi_view "cms/main/navi"

  private
    def set_crumbs
      @crumbs << [:"cms.content", action: :index]
    end

  public
    def index
      @notices = Cms::Notice.site(@cur_site).and_public.
        target_to(@cur_user).
        page(1).per(1)

      @model = Cms::Node
      self.menu_view_file = nil

      @mod = params[:mod]
      cond = {}
      cond[:route] = /^#{Regexp.escape(@mod)}\// if @mod.present?

      @items = Cms::Node.site(@cur_site).
        allow(:read, @cur_user).
        where(cond).
        where(shortcut: :show).
        order_by(filename: 1).
        page(params[:page]).per(100)
    end
end
