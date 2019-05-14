require 'uri'

class SessionsController < ApplicationController

  @@openid_url_base  = "https://publiclab.org/people/"
  @@openid_url_suffix = "/identity"


  def login
    if logged_in?
      redirect_to "/"
    else
      @referer = params[:back_to]
    end
  end

  def new
    back_to = params[:back_to]
     # we pass a temp username; it'll be overwritten by the real one in PublicLab.org's response:
    open_id = 'x'
    openid_url = URI.decode(open_id)
    # here it is localhost:3000/people/admin/identity for admin
    # possibly user is providing the whole URL
    if openid_url.include? "publiclab"
      if openid_url.include? "http"
        # params[:subaction] contains the value of the provider
        # provider implies ['github', 'google_oauth2', 'twitter', 'facebook']
        if params[:subaction]
          # provider based authentication
          url = openid_url + "/" + params[:subaction]
        else
          # form based authentication
          url = openid_url
        end
      end
    else
      if params[:subaction]
        # provider based authentication
        url = @@openid_url_base + openid_url + @@openid_url_suffix + "/" + params[:subaction]
      else
        # form based authentication
        url = @@openid_url_base + openid_url + @@openid_url_suffix
      end
    end
    openid_authentication(url, back_to)
  end

  def failed_login(message = "Authentication failed.")
    flash[:danger] = message
    redirect_to '/'
  end

  def successful_login(back_to, id)
    session[:user_id] = @current_user.id
    flash[:success] = "You have successfully logged in."
    if id
      redirect_to '/sites/' + id.to_s + '/upload'
    else
      if back_to
        back_to = "/dashboard" if back_to == "/"
        redirect_to back_to
      else
        redirect_to '/sites'
      end
    end
  end

  def logout
    session[:user_id] = nil
    flash[:success] = "You have successfully logged out."
    redirect_to '/'
  end

  # only on local installations and during testing, to bypass OpenID; add "local: true" to config/config.yml
  def local
    if APP_CONFIG["local"] == true && @current_user = User.find_by_login(params[:login])
      successful_login '', nil
    else
      flash[:error] = "Forbidden"
      redirect_to "/"
    end
  end

  protected

  def openid_authentication(openid_url, back_to)
    #puts openid_url
    authenticate_with_open_id(openid_url, :required => [:nickname, :email, :fullname]) do |result, identity_url, registration|
      dummy_identity_url = identity_url
      dummy_identity_url = dummy_identity_url.split('/')
      if dummy_identity_url.include?('github') || dummy_identity_url.include?('google_oauth2') || dummy_identity_url.include?('facebook') || dummy_identity_url.include?('twitter')
        identity_url = dummy_identity_url[0..-2].join('/')
      end
      # we splice back in the real username from PublicLab.org's response
      identity_url = identity_url.split('/')[0..-2].join('/') + '/' + registration['nickname']
      if result.successful?
        @user = User.find_by_identity_url(identity_url)

        if not @user
          @user = User.new
          @user.login = registration['nickname']
          @user.email = registration['email']
          @user.identity_url = identity_url
          hash = registration['fullname'].split(':')
          @user.role =  hash[1].split('=')[1]

          begin
            @user.save!
          rescue ActiveRecord::RecordInvalid => invalid
            puts invalid
            failed_login "User can not be associated to local account. Probably the account already exists with different case!"
            return
          end
        end

        nonce = params[:n]
        if nonce
          tmp = Sitetmp.find_by nonce: nonce
          if tmp
            data = tmp.attributes
            data.delete("nonce")
            site = Site.new(data)
            site.save
            tmp.destroy
          end
        end
        @current_user = @user
        if site
          successful_login back_to, site.id
        else
          successful_login back_to, nil
        end
      else
        failed_login result.message
        return false
      end
    end
  end

end
