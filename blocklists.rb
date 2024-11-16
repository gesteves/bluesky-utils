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
      puts "Getting blocks for #{email}\n\n"

      # Retrieve blocked accounts
      blocks = bluesky.get_blocks

      # Add each blocked account to each list
      yaml_data['lists'].each do |list|
        list_uri = list['uri']

        blocks.map { |block| block["did"] }.each do |blocked_did|
          begin
            bluesky.add_user_to_list(blocked_did, list_uri)
            puts "Added DID #{blocked_did} to list #{list_uri}"
          rescue StandardError => e
            puts "Failed to add DID #{blocked_did} to list #{list_uri}: #{e.message}"
          end
          begin
            bluesky.unblock(blocked_did)
            puts "  Unblocked #{blocked_did}"
          rescue StandardError => e
            puts "Failed to unblock DID #{blocked_did}: #{e.message}"
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
