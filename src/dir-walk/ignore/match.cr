module Dir::Walk::Ignore
  enum MatchType : UInt8
    None
    Ignore
    Whitelist
  end

  struct Match
    getter type : MatchType

    def initialize(@type : MatchType = MatchType::None)
    end

    def self.none : self
      new(MatchType::None)
    end

    def self.ignore : self
      new(MatchType::Ignore)
    end

    def self.whitelist : self
      new(MatchType::Whitelist)
    end

    def none? : Bool
      @type == MatchType::None
    end

    def ignore? : Bool
      @type == MatchType::Ignore
    end

    def whitelist? : Bool
      @type == MatchType::Whitelist
    end

    def invert : self
      case @type
      when MatchType::None
        self
      when MatchType::Ignore
        Match.whitelist
      else
        Match.ignore
      end
    end

    def or(other : self) : self
      none? ? other : self
    end
  end
end
