require 'sinatra'
require 'sinatra/reloader'
require 'pg'
require 'sinatra/cookies'
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

  # sql = """
  #   SELECT users.name, content, timestamp
  #   FROM posts
  #   JOIN users
  #   ON user_id = users.id
  #   ORDER BY timestamp DESC;
  # """
  # @posts = client.exec_params(sql)

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
  if session[:user] != nil
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
  redirect '/'
end

get '/sign_in' do
  if session[:user] != nil
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

