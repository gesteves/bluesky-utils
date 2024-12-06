require 'yaml'
require 'httparty'
require 'time'
require_relative 'bluesky'

# Load the YAML file
yaml_data = YAML.load_file('config.yml')

# Collect all blocked accounts and add them to each list
if yaml_data['accounts'] && yaml_data['lists']
  accounts = yaml_data['accounts']
  lists = yaml_data['lists']

  accounts.each do |name, account|
    email = account['email']
    password = account['password']

    begin
      # Initialize a Bluesky instance
      bluesky = Bluesky.new(email: email, password: password)

      puts "\nFetching accounts blocked by #{name} (#{email})…"
      # Retrieve blocked accounts
      blocks = bluesky.get_blocks

      puts "#{name} is blocking #{blocks.size} accounts."
      next if blocks.empty?

      # Add each blocked account to each list
      lists.each do |list|
        list_account_name = list['account']
        url = list['url']

        if accounts[list_account_name]
          list_email = accounts[list_account_name]['email']
          list_password = accounts[list_account_name]['password']
          list_owner = Bluesky.new(email: list_email, password: list_password)

          puts "Adding #{blocks.size} accounts to #{url} (owned by #{list_account_name})"
          blocks.each do |block|
            did = block["did"]
            handle = block["handle"]
            begin
              list_owner.add_user_to_list(did, url)
              puts " #{handle} (#{did}) added to list."
            rescue StandardError => e
              puts " [ERROR] Failed to add #{handle} (#{did}) to #{url}: #{e.message}"
            end
            begin
              bluesky.unblock(did)
            rescue StandardError => e
              puts " [ERROR] Failed to unblock #{handle} (#{did}): #{e.message}"
            end
          end
        else
          puts " [ERROR] List owner account '#{list_account_name}' not found in accounts."
        end
      end

    rescue StandardError => e
      puts "Failed to process account #{name} (#{email}): #{e.message}"
    end
  end
else
  puts 'No accounts or lists found in the YAML file.'
end
