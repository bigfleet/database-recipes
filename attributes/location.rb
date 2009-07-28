database Mash.new unless attribute?("database")
database[:location] = `hostname -f`.downcase.strip unless database.has_key?(:location)