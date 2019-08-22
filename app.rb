require 'sinatra'
require 'sinatra/reloader'
require 'pg'
require 'sinatra/cookies'
require 'pry'
# require './import/twitter_scraping.rb'
require 'open-uri'
enable :sessions

client = PG::connect(
  :host => "localhost",
  :user => 'ryama', :password => '',
  :dbname => "cb_graduation")

get '/' do
  if logged_in?
    redirect '/index'
  end

  erb :top
end

get '/index' do
  unless logged_in?
    redirect '/'
  end

  @contents = get_contents(client)
  @total = 0
  @contents.each do |content|
    @total += content["counter"].to_i
  end
  erb :index
end

post '/post' do
  user_id = session[:user][:id]
  content = params[:content]
  timestamp = Time.now
  sql = """
    INSERT INTO posts(user_id, content, timestamp)
    VALUES($1, $2, $3)
  """
  client.exec_params(sql, [user_id, content, timestamp])
  redirect '/index'
end

get '/sign_up' do
  if logged_in?
    redirect '/index'
  end

  erb :sign_up
end

post '/sign_up' do
  sql = "SELECT * FROM users WHERE email = $1;"
  if client.exec_params(sql, [params[:email]]).ntuples != 0
    redirect '/sign_up'
  end
  name = params[:name]
  email = params[:email]
  password = Digest::SHA256.new.update(params[:password]).hexdigest
  client.exec_params('INSERT INTO users(name, email, password) VALUES($1, $2, $3);', [name, email, password])
  id = client.exec_params('SELECT id FROM users WHERE email = $1 AND password = $2;', [email, password])[0]["id"]

  set_user(id, name, email)
  redirect '/index'
end

get '/sign_in' do
  if logged_in?
    redirect '/index'
  end

  erb :sign_in
end

post '/sign_in' do
  email = params[:email]
  password = Digest::SHA256.new.update(params[:password]).hexdigest
  sql = "SELECT * FROM users WHERE email = $1 AND password = $2"

  if client.exec_params(sql, [email, password]).ntuples == 0
    redirect '/sign_in'
  end

  user = client.exec_params(sql, [email, password])[0]
  set_user(user["id"], user["name"], user["email"])
  
  redirect '/index'
end

def logged_in?
  session[:user] != nil
end

def set_user(id, name, email)
  session[:user] = {
    id: id,
    name: name,
    email: email
  }
end

get '/sign_out' do
  session[:user] = nil
  redirect '/'
end

get '/setting' do
  unless logged_in?
    redirect '/'
  end

  @contents = get_contents(client)
  erb :setting
end

post '/add' do
  content = params["name"].gsub(" ", "").gsub("　", "")
  sql = "SELECT * FROM contents WHERE name = $1;"
  contents = client.exec_params(sql, [content])
  if not content.empty? and contents.ntuples == 0
    insert_sql = "INSERT INTO contents (name) values ($1);"
    client.exec_params(insert_sql, [params["name"]])
    contents = client.exec_params(sql, [content])
  end

  sql = """
  SELECT * FROM users_contents
  JOIN contents ON content_id = contents.id
  WHERE user_id = $1 AND contents.name = $2;
  """
  users_content = client.exec_params(sql, [session[:user][:id], content])
  if users_content.ntuples == 0
    sql = """
    INSERT INTO users_contents (user_id, content_id)
    VALUES ($1, $2);
    """
    client.exec_params(sql, [session[:user][:id], contents[0]["id"]])
  end

  redirect '/setting'
end

post '/delete' do
  content_id = params["id"]
  sql = """
  DELETE FROM users_contents
  WHERE user_id = $1 AND content_id = $2;
  """
  client.exec_params(sql, [session[:user][:id], content_id])
  redirect '/setting'
end

def get_contents(client)
  sql = """
  SELECT * FROM users_contents
  JOIN contents ON content_id = contents.id
  WHERE user_id = $1;
  """
  client.exec_params(sql, [session[:user][:id]])
end

post '/input' do
  time_input(client, params["id"].to_i, params["time"].to_i)
  redirect '/index'
end

def time_input(client, content_id, time)
  time_get = """
  SELECT counter FROM users_contents
  WHERE user_id = $1
  AND content_id = $2;
  """
  old_time = client.exec_params(time_get, [session[:user][:id], content_id])

  if old_time.ntuples > 0
    time += old_time[0]["counter"].to_i

    input_time = """
    UPDATE users_contents SET counter = $1
    WHERE user_id = $2
    AND content_id = $3;
    """
    client.exec_params(input_time, [time, session[:user][:id], content_id])
  end
end

get '/get_tweet' do
  unless logged_in?
    redirect '/'
  end

  sql = "SELECT latest_tweet FROM users WHERE id = $1"
  
  latest_tweet_date = client.exec_params(sql, [session[:user][:id]])[0]["latest_tweet"]
  tweet_data = get_tweets_up_to_specified_date(latest_tweet_date)

  sql = "UPDATE users set latest_tweet = $1 WHERE id = $2"
  client.exec_params(sql, [tweet_data[:latest_tweet_date], session[:user][:id]])

  contents = get_contents(client)
  tweet_data[:tweets].each do |tweet|
    add_time = nil
    target_content = nil
    if tweet[/がくろぐ/]
      if tweet.delete("^0-9").to_i > 0
        add_time = tweet.delete("^0-9").to_i
      end
      contents.each do |content|
        if tweet.include?(content["name"])
          target_content = content["id"]
          break
        end
      end

      if add_time && target_content
        time_input(client, target_content, add_time)
      end
    end
  end

  redirect '/index'
end

post '/edit_name' do
  sql = "UPDATE users SET name = $1 WHERE id = $2"
  client.exec_params(sql, [params["name"], session[:user][:id]])
  session[:user][:name] = params["name"]
  redirect '/setting'
end



class TweetData

  def initialize(html)
    # アカウント名を取得
    @account = html[/data-screen-name="(.+?)"/, 1]

    # tweet日時を取得 [yyyy, mm, dd]
    @time_and_day = html[%r{<small class="time">(.+?)</small>}m][/title="(.+?)"/, 1]
    if @time_and_day =~ /(\d*):(\d*) - (\d*).+?(\d*).+?(\d*).+/
      @time_and_day = "#{fm(4, $3)}/#{fm(2, $4)}/#{fm(2, $5)} #{fm(2, $1)}:#{fm(2, $2)}"
    end

    # tweet内容のみを抽出
    @tweet = html[%r{<div class="js-tweet-text-container">(.+?)</div>}m][%r{<p.+?>(.+?)</p>}m, 1]
    # ハッシュタグだけ救出
    @tweet += "#"+$1 if @tweet =~ %r{<s>#</s><b>(.*)</b>}
    # 画像があればリンクを削除
    @tweet = $1 if @tweet =~ %r{(.*?)<a.+</a>}
    # 絵文字なども削除
    while @tweet =~ /<img .+? title="(.+?)" .+?>/
      img = "[" + $1 + "]"
      @tweet = @tweet.sub(/<img.+?>/, img)
    end
  end

  def account
    @account
  end

  def time_and_day
    @time_and_day
  end

  def tweet
    @tweet
  end

  private
  def fm(digit, num)
    format("%0#{digit}d", num.to_i)
  end
end


# アカウント名からトップページのhtmlを取得
def get_top_html
  url = "https://twitter.com/#{session[:user][:name]}"
  open(url).read
end

# htmlを与えるとmin-positionを返す
def get_min_position(top_html)
  top_html[/data-min-position="(.+?)"/, 1]
end

# min_positionからjsonを取得，次のmin_positionとhtmlに分割
def get_next_json(min_position)
  url = "https://twitter.com/i/profiles/show/#{session[:user][:name]}/timeline/tweets?include_available_features=1&include_entities=1&max_position=#{min_position}&reset_error_state=false"
  json_data = open(url).read
  
  # 正規表現によりそれぞれを抜き出す
  next_min = json_data[/"min_position":"(.+?)"/, 1]
  next_html = json_data[/"items_html":"(.+?)","new_latent_count"/, 1]

  # htmlの内容が崩れているので修正
  # \" -> "，\/ -> /，改行文字を改行するように再連結
  next_html = next_html.gsub(/\\u([\da-fA-F]{4})/) { [$1].pack('H*').unpack('n*').pack('U*') }
  # 何故かUTF-8で怒られるのでencode
  next_html = next_html.force_encoding('utf-8')
  next_html = next_html.encode("utf-16be", "utf-8", :invalid => :replace, :undef => :replace, :replace => '?').encode("utf-8")

  revised_html = ""
  next_html.split('\n').each do |line|
    revised_html << line.gsub(%r{\\"|\\/}, '\"'=>'"', '\/'=>'/') << "\n"
  end

  {"min_position" => next_min, "html" => revised_html}
end

# htmlからtweet情報を取得
def pull_out_tweet_data(html)
  # tweetのデータが入っているlistを正規表現で切り取り
  tweet_data = html.scan(%r{<li class="js-stream-item stream-item stream-item.+?\n\n</li>\n\n}m)
  tweet_data.each do |data|
    $tweet_data_list << TweetData.new(data)
  end
end

# 取得したtweetデータを表示する
def print_tweets
  $tweet_data_list.each do |tweet_data|
    puts "-"*50
    puts tweet_data.time_and_day
    puts "@" + tweet_data.account + "さんのTweet"
    puts tweet_data.tweet
    puts "-"*50
  end
end

# 第一引数が第二引数より新しい日付or同じ日ならtreu
def is_new_date(date1, date2)
  # date1 = "%04d"%date1[0] + "%02d"%date1[1] + "%02d"%date1[2]
  # date2 = "%04d"%date2[0] + "%02d"%date2[1] + "%02d"%date2[2]
  date1 > date2
end

# 日付をしていし，そこまでのtweetをtextで保存
def get_tweets_up_to_specified_date(specify_date)
  $tweet_data_list = []
  # tweets_file = File.open("./Tweets/#{session[:user][:name]}", "w")
  top_html = get_top_html
  pull_out_tweet_data(top_html)
  min_position = get_min_position(top_html)

  get_flag = true
  tweets = []
  if $tweet_data_list.empty?
    Time.now.to_s[/(\d*-)(\d*)(-\d*.*):\d* +\d*/]
    {tweets: tweets, latest_tweet_date: ($1+format("%02d",$2.to_i-1)+$3).gsub("-", "/")}
  else
    latest_tweet_date = $tweet_data_list[0].time_and_day
    while(get_flag) do
      $tweet_data_list.each do |tweet|
        # 自分のtweetだけ抜き取る
        if tweet.account == session[:user][:name]
          if is_new_date(tweet.time_and_day, specify_date)
            # tweets_file.puts(tweet.tweet)
            tweets << tweet.tweet
          else
            get_flag = false
            break
          end
          # p tweet.time_and_day
        end
      end

      # 使用済みtweet_dataの初期化
      $tweet_data_list = []

      if get_flag
        next_data = get_next_json(min_position)
        pull_out_tweet_data(next_data["html"])
        min_position = next_data["min_position"]
        p min_position
      end
    end

    # tweets_file.close
    {tweets: tweets, latest_tweet_date: latest_tweet_date}
  end
end

