require 'sinatra'
require 'sinatra/reloader'
require 'pg'
require 'sinatra/cookies'
require 'pry'
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
