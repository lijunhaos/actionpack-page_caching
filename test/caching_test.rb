require "abstract_unit"
require "mocha/setup"

CACHE_DIR = "test_cache"
# Don't change "../tmp" cavalierly or you might hose something you don't want hosed
TEST_TMP_DIR = File.expand_path("../tmp", __FILE__)
FILE_STORE_PATH = File.join(TEST_TMP_DIR, CACHE_DIR)

module PageCachingTestHelpers
  def setup
    super

    @routes = ActionDispatch::Routing::RouteSet.new

    FileUtils.rm_rf(File.dirname(FILE_STORE_PATH))
    FileUtils.mkdir_p(FILE_STORE_PATH)
  end

  def teardown
    super

    FileUtils.rm_rf(File.dirname(FILE_STORE_PATH))
    @controller.perform_caching = false
  end

  private

    def assert_page_cached(action, options = {})
      message = options[:message] || "#{action} should have been cached"
      assert page_cached?(action, options), message
    end

    def assert_page_not_cached(action, options = {})
      message = options[:message] || "#{action} should have been cached"
      assert !page_cached?(action, options), message
    end

    def page_cached?(action, options = {})
      path = options[:path] || FILE_STORE_PATH
      format = options[:format] || "html"
      controller = options[:controller] || self.class.name.underscore

      File.exist? "#{path}/#{controller}/#{action}.#{format}"
    end

    def draw(&block)
      @routes = ActionDispatch::Routing::RouteSet.new
      @routes.draw(&block)
      @controller.extend(@routes.url_helpers)
    end
end

class CachingMetalController < ActionController::Metal
  abstract!

  include AbstractController::Callbacks
  include ActionController::Caching

  self.page_cache_directory = FILE_STORE_PATH
  self.cache_store = :file_store, FILE_STORE_PATH
end

class PageCachingMetalTestController < CachingMetalController
  caches_page :ok

  def ok
    self.response_body = "ok"
  end
end

class PageCachingMetalTest < ActionController::TestCase
  include PageCachingTestHelpers
  tests PageCachingMetalTestController

  def test_should_cache_get_with_ok_status
    draw do
      get "/page_caching_metal_test/ok", to: "page_caching_metal_test#ok"
    end

    get :ok
    assert_response :ok
    assert_page_cached :ok
  end
end

ActionController::Base.page_cache_directory = FILE_STORE_PATH

class CachingController < ActionController::Base
  abstract!

  self.cache_store = :file_store, FILE_STORE_PATH
end

class PageCachingTestController < CachingController
  self.page_cache_compression = :best_compression

  caches_page :ok, :no_content, if: Proc.new { |c| !c.request.format.json? }
  caches_page :found, :not_found
  caches_page :about_me
  caches_page :default_gzip
  caches_page :no_gzip, gzip: false
  caches_page :gzip_level, gzip: :best_speed

  def ok
    head :ok
  end

  def no_content
    head :no_content
  end

  def found
    redirect_to action: "ok"
  end

  def not_found
    head :not_found
  end

  def custom_path
    render html: "Super soaker"
    cache_page("Super soaker", "/index.html")
  end

  def default_gzip
    render html: "Text"
  end

  def no_gzip
    render html: "PNG"
  end

  def gzip_level
    render html: "Big text"
  end

  def expire_custom_path
    expire_page("/index.html")
    head :ok
  end

  def trailing_slash
    render html: "Sneak attack"
  end

  def about_me
    respond_to do |format|
      format.html { render html: "I am html" }
      format.xml  { render xml: "I am xml" }
    end
  end
end

class PageCachingTest < ActionController::TestCase
  include PageCachingTestHelpers
  tests PageCachingTestController

  def test_page_caching_resources_saves_to_correct_path_with_extension_even_if_default_route
    draw do
      get "posts.:format", to: "posts#index", as: :formatted_posts
      get "/", to: "posts#index", as: :main
    end

    defaults = { controller: "posts", action: "index", only_path: true }

    assert_equal "/posts.rss", @routes.url_for(defaults.merge(format: "rss"))
    assert_equal "/", @routes.url_for(defaults.merge(format: nil))
  end

  def test_should_cache_head_with_ok_status
    draw do
      get "/page_caching_test/ok", to: "page_caching_test#ok"
    end

    head :ok
    assert_response :ok
    assert_page_cached :ok, message: "head with ok status should have been cached"
  end

  def test_should_cache_get_with_ok_status
    draw do
      get "/page_caching_test/ok", to: "page_caching_test#ok"
    end

    get :ok
    assert_response :ok
    assert_page_cached :ok, message: "get with ok status should have been cached"
  end

  def test_should_cache_with_custom_path
    draw do
      get "/page_caching_test/custom_path", to: "page_caching_test#custom_path"
    end

    get :custom_path
    assert_page_cached :index, controller: "."
  end

  def test_should_expire_cache_with_custom_path
    draw do
      get "/page_caching_test/custom_path", to: "page_caching_test#custom_path"
      get "/page_caching_test/expire_custom_path", to: "page_caching_test#expire_custom_path"
    end

    get :custom_path
    assert_page_cached :index, controller: "."

    get :expire_custom_path
    assert_page_not_cached :index, controller: "."
  end

  def test_should_gzip_cache
    draw do
      get "/page_caching_test/custom_path", to: "page_caching_test#custom_path"
      get "/page_caching_test/expire_custom_path", to: "page_caching_test#expire_custom_path"
    end

    get :custom_path
    assert_page_cached :index, controller: ".", format: "html.gz"

    get :expire_custom_path
    assert_page_not_cached :index, controller: ".", format: "html.gz"
  end

  def test_should_allow_to_disable_gzip
    draw do
      get "/page_caching_test/no_gzip", to: "page_caching_test#no_gzip"
    end

    get :no_gzip
    assert_page_cached :no_gzip, format: "html"
    assert_page_not_cached :no_gzip, format: "html.gz"
  end

  def test_should_use_config_gzip_by_default
    draw do
      get "/page_caching_test/default_gzip", to: "page_caching_test#default_gzip"
    end

    @controller.expects(:cache_page).with(nil, nil, Zlib::BEST_COMPRESSION)
    get :default_gzip
  end

  def test_should_set_gzip_level
    draw do
      get "/page_caching_test/gzip_level", to: "page_caching_test#gzip_level"
    end

    @controller.expects(:cache_page).with(nil, nil, Zlib::BEST_SPEED)
    get :gzip_level
  end

  def test_should_cache_without_trailing_slash_on_url
    @controller.class.cache_page "cached content", "/page_caching_test/trailing_slash"
    assert_page_cached :trailing_slash
  end

  def test_should_obey_http_accept_attribute
    draw do
      get "/page_caching_test/about_me", to: "page_caching_test#about_me"
    end

    @request.env["HTTP_ACCEPT"] = "text/xml"
    get :about_me
    assert_equal "I am xml", @response.body
    assert_page_cached :about_me, format: "xml"
  end

  def test_cached_page_should_not_have_trailing_slash_even_if_url_has_trailing_slash
    @controller.class.cache_page "cached content", "/page_caching_test/trailing_slash/"
    assert_page_cached :trailing_slash
  end

  def test_should_cache_ok_at_custom_path
    draw do
      get "/page_caching_test/ok", to: "page_caching_test#ok"
    end

    @request.env["PATH_INFO"] = "/index.html"
    get :ok
    assert_response :ok
    assert_page_cached :index, controller: "."
  end

  [:ok, :no_content, :found, :not_found].each do |status|
    [:get, :post, :patch, :put, :delete].each do |method|
      unless method == :get && status == :ok
        define_method "test_shouldnt_cache_#{method}_with_#{status}_status" do
          draw do
            get "/page_caching_test/ok", to: "page_caching_test#ok"
            match "/page_caching_test/#{status}", to: "page_caching_test##{status}", via: method
          end

          send(method, status)
          assert_response status
          assert_page_not_cached status, message: "#{method} with #{status} status shouldn't have been cached"
        end
      end
    end
  end

  def test_page_caching_conditional_options
    draw do
      get "/page_caching_test/ok", to: "page_caching_test#ok"
    end

    get :ok, format: "json"
    assert_page_not_cached :ok
  end

  def test_page_caching_directory_set_as_pathname
    begin
      ActionController::Base.page_cache_directory = Pathname.new(FILE_STORE_PATH)

      draw do
        get "/page_caching_test/ok", to: "page_caching_test#ok"
      end

      get :ok
      assert_response :ok
      assert_page_cached :ok
    ensure
      ActionController::Base.page_cache_directory = FILE_STORE_PATH
    end
  end

  def test_page_caching_directory_set_on_controller_instance
    draw do
      get "/page_caching_test/ok", to: "page_caching_test#ok"
    end

    file_store_path = File.join(TEST_TMP_DIR, "instance_cache")
    @controller.page_cache_directory = file_store_path

    get :ok
    assert_response :ok
    assert_page_cached :ok, path: file_store_path
  end
end
