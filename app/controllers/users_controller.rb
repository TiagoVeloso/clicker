class UsersController < ApplicationController
  MINIMUM_CREDITS ||= Configurable.minimum_credits

  VALIDATION_REG = /You have just increased ([a-zA-Z0-9]+)'s population to (\d{1,3}(,|.)?\d{1,3})+\./

  before_filter :authenticate_admin!, :except => [:index, :show, :new, :click, :create]
  
  helper_method :sort_column, :sort_direction

  # GET /users
  # GET /users.xml
  def index
    @users ||= User.ordered_by_credits.to_a
    clickable_users(@users)
    frozen_users(@users)
    legend_users(@users)
    sorted_users(@users)

    session.delete(:click_order)
    session.delete(:current_user)
    @selected_user = nil

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @users }
    end
  end

  # GET /users
  # GET /users.xml
  def search
    @users ||= User.where("name LIKE ?","%#{params[:search]}%").order(sort_column + " " + sort_direction)
    
    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @users }
    end
  end

  # GET /users/1
  # GET /users/1.xml
  def show
    @user = User.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @user }
    end
  end

  # GET /users/new
  # GET /users/new.xml
  def new
    @user = User.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @user }
    end
  end

  # GET /users/new
  # GET /users/new.xml
  def new_batch
    @users

    respond_to do |format|
      format.html # new_batch.html.erb
      format.xml  { render :xml => @user }
    end
  end

  # GET /users/1/edit
  def edit
    @user = User.find(params[:id])
  end

  # POST /users
  # POST /users.xml
  def create
    if params[:user][:urls]
      @urls = params[:user][:urls].split(/[\r\n]+/)
      @urls.each do |url|
        @user = User.new(:url => url)
        @user.save
      end
      redirect_to(users_path, :notice => "#{helpers.pluralize(@urls.length, 'user was added', 'users were added')}")
      return
    else
      @user = User.new(params[:user])
    end

    respond_to do |format|
      if @user.save
        format.html { redirect_to(users_path, :notice => @user.name + ' was successfully created.') }
        format.xml  { render :xml => @user, :status => :created, :location => @user }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @user.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /users/1
  # PUT /users/1.xml
  def update
    @user = User.find(params[:id])

    respond_to do |format|
      if @user.update_attributes(params[:user])
        format.html { redirect_to(@user, :notice => @user.name + ' was successfully updated.') }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @user.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /users/
  # PUT /users/
  def reset_counters
    changed = User.reset_counters

    respond_to do |format|
      format.html { redirect_to(:back, :notice => "#{helpers.pluralize(changed, 'user was reset', 'users were reset')}") }
      format.xml  { head :ok }
    end
  end

  # DELETE /users/1
  # DELETE /users/1.xml
  def destroy
    @user = User.find(params[:id])
    @user.destroy

    respond_to do |format|
      format.html { redirect_to users_path, :notice => @user.name + ' was successfully deleted.' }
      format.xml  { head :ok }
    end
  end

  # DELETE /users/
  # DELETE /users/
  def destroy_frozen
    deleted = User.delete_frozen

    respond_to do |format|
      format.html { redirect_to :back, :notice => "#{helpers.pluralize(deleted, 'inactive user was', 'inactive users were')} successfully deleted." }
      format.xml  { head :ok }
    end
  end
  
  # DELETE /users/
  # DELETE /users/
  def destroy_selected
    # User.destroy_all(params[:users_id])
    deleted = User.delete_all(:id => params[:user_ids])
    
    respond_to do |format|
      format.html { redirect_to :back, :notice => "#{helpers.pluralize(deleted, 'user was', 'users were')} successfully deleted." }
      format.xml  { head :ok }
    end
  end

  # GET /users/1/click
  # GET /users/1/click.xml
  def click
    if params[:commit] == 'Delete Selected'
      destroy_selected and return
    end
    
    if params[:start_user]
      @user = User.find(params[:start_user])
    else
      @user = User.find(params[:id])
    end
    
    session[:click_order] ||= load_click_order
    session[:current_user] ||= load_current_user
    @clicked_user ||= load_clicked_user
    
    @next_user = next_in_array @user.id, session[:click_order]

    if !session[:current_user].blank? && @selected_user.nil?
      @selected_user ||= User.find(session[:current_user])
    else
      flash[:error] = 'You must select a user.'
      redirect_to :action => 'index' and return
    end
    
    process_click
    
    if params[:commit] == 'End Clicking'
      redirect_to :action => 'index' and return
    end

    respond_to do |format|
      format.html # click.html.erb
      format.xml  { render :xml => @user }
    end
  end

  private
  
  def sort_column
    columns ||= User.column_names.push('clicks_given - clicks_received').include?(params[:sort]) ? params[:sort] : 'name'
  end
  
  def sort_direction
    %w[asc desc].include?(params[:direction]) ? params[:direction] : 'desc'
  end

  def all_users
    @users ||= User.ordered_by_credits.to_a
  end

  def clickable_users(users)
    @clickables ||= users.select { |u| u.credits >= MINIMUM_CREDITS && !u.legend }.to_a
  end

  def frozen_users(users)
    @frozen ||= users.select { |u| u.credits < MINIMUM_CREDITS && !u.legend }.to_a
  end

  def legend_users(users)
    @legends ||= @users.select {|u| u.legend }.to_a
  end

  def sorted_users(users)
    @sorted_by_name ||= users.sort { |a,b| a.name.downcase <=> b.name.downcase }
  end

  def next_in_array(elem,array)
    array[ array.index(elem) + 1 ]
  end

  def load_click_order
    if session[:click_order].blank?
      all_users
      clickable_users @users 
      @clickables.collect { |u| u.id }
    end
  end

  def load_current_user
    if !params[:user].blank? && !params[:user][:id].blank?
      session[:current_user] = params[:user][:id]
    elsif !params["selected_user" + @user.id.to_s].blank?
      session[:current_user] = params["selected_user" + @user.id.to_s].to_i
    end
  end

  def load_clicked_user
    if !params[:clicked_user].blank?
      User.find(params[:clicked_user])
    end
  end
  
  def update_credits
    User.transaction do
      @clicked_user.lose_credit
      @selected_user.gain_credit
    end
  end

  def process_click
    if @clicked_user != @selected_user
      if params[:validation_line]
        m = params[:validation_line].match(VALIDATION_REG)
      end
      case params[:commit]
      when 'Next User'
        if m && m[1] == @clicked_user.name
          update_credits
          flash.now[:notice] = 'Successfully clicked ' + @clicked_user.name + '.'
        else
          flash.now[:error] = 'Invalid click for ' + @clicked_user.name + '.'
        end
      when 'End Clicking'
        if m && m[1] == @clicked_user.name
          update_credits
          flash[:notice] = 'Successfully clicked ' + @clicked_user.name + '.'
        else
          flash[:error] = 'Invalid click for ' + @clicked_user.name + '.'
        end
      when 'Skip User'
        flash.now[:error] = 'Skipped ' + @clicked_user.name + '.'
      end
    else
      flash[:notice] = 'Successfully clicked ' + @clicked_user.name + '.'
    end
  end
end
