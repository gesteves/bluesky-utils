require 'yaml'
require 'httparty'
require 'time'
require_relative 'bluesky'

# Load the YAML file
yaml_data = YAML.load_file('config.yml')

# Collect all blocked accounts and add them to each list
if yaml_data['accounts'] && yaml_data['lists']
  yaml_data['accounts'].each do |account|
    email = account['email']
    password = account['password']

    begin
      # Initialize a Bluesky instance
      bluesky = Bluesky.new(email: email, password: password)

      puts "\nFetching accounts blocked by #{email}…"
      # Retrieve blocked accounts
      blocks = bluesky.get_blocks

      puts "#{email} is blocking #{blocks.size} accounts."
      next if blocks.empty?

      # Add each blocked account to each list
      yaml_data['lists'].each do |list|
        url = list['url']
        puts "Adding #{blocks.size} accounts to #{url}"
        blocks.each do |block|
          did = block["did"]
          handle = block["handle"]
          begin
            bluesky.add_user_to_list(did, url)
            puts " #{handle}"
          rescue StandardError => e
            puts " [ERROR] Failed to add #{handle} to #{url}: #{e.message}"
          end
          begin
            bluesky.unblock(did)
          rescue StandardError => e
            puts " [ERROR] Failed to unblock #{handle}: #{e.message}"
          end
        end
      end

    rescue StandardError => e
      puts "Failed to process account #{email}: #{e.message}"
    end
  end
else
  puts 'No accounts or lists found in the YAML file.'
end
