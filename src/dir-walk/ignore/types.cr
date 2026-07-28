module Dir::Walk::Ignore
  class Types
    def self.empty : self
      new
    end

    def empty? : Bool
      true
    end

    def matched(path : String) : Match
      Match.none
    end
  end
end
