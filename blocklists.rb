require 'yaml'
require 'httparty'
require 'time'
require_relative 'bluesky'

# Load the YAML file
yaml_data = YAML.load_file('config.yml')

if yaml_data['accounts']
  accounts = yaml_data['accounts']
  all_lists = []

  accounts.each do |name, account|
    email = account['email']
    password = account['password']

    begin
      # Initialize a Bluesky instance
      bluesky = Bluesky.new(email: email, password: password)
      puts "\nFetching moderation lists for @#{name}…"
      lists = bluesky.get_list_blocks["lists"] || []
      all_lists += lists

    rescue StandardError => e
      puts "Failed to process account #{name} (#{email}): #{e.message}"
    end
  end

  all_lists = all_lists.uniq { |list| list["uri"] }

  accounts.each do |name, account|
    email = account['email']
    password = account['password']

    begin
      puts "\nBlocking lists for @#{name}…"
      # Initialize a Bluesky instance
      bluesky = Bluesky.new(email: email, password: password)
      lists = bluesky.get_list_blocks["lists"] || []
      unsubscribed_lists = all_lists.reject { |list| lists.any? { |l| l["uri"] == list["uri"] } }
      puts " No new lists to block." if unsubscribed_lists.empty?
      unsubscribed_lists.each do |list|
        puts " #{list["name"]}"
        bluesky.block_list(list["uri"])
      end

    rescue StandardError => e
      puts "Failed to process account #{name} (#{email}): #{e.message}"
    end
  end
else
  puts 'No accounts or lists found in the YAML file.'
end

