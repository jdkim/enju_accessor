$LOAD_PATH << File.dirname(__FILE__) + '/lib'

require './enju_accessor_ws'
run Sinatra::Application