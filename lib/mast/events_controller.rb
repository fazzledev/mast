module Mast
  # Takes the widget's events, one action per event type, the way a Rails
  # controller takes requests. Each event is JSON with a `type`, the fields
  # below, and `at`, the widget's clock in milliseconds.
  #
  #   start          attempt, site, label        a blocked site's switch was flipped
  #   passage        attempt, seq, text, source, url
  #                                              a passage went on screen
  #   leave          attempt, seq, chars         it was swapped, or the attempt ended mid-typing
  #   typed          attempt, seq, chars, typing_ms, wpm, peak_wpm, typos
  #                                              it was typed out in full
  #   end            attempt, outcome, reason    the attempt ended
  #   relock         site, relock_at             an unblocked site's relock time became known
  #   blocked_again  site                        an unblocked site was seen blocked again
  class EventsController
    class UnknownEvent < StandardError; end

    # `end` is a keyword, so its action is `finish`.
    ACTIONS = {
      "start" => :start, "passage" => :passage, "leave" => :leave, "typed" => :typed,
      "end" => :finish, "relock" => :relock, "blocked_again" => :blocked_again,
    }.freeze

    def self.dispatch(event) = new(event).process

    attr_reader :params

    def initialize(params)
      @params = params
    end

    def process
      action = ACTIONS.fetch(params["type"]) { raise UnknownEvent, "unknown event type: #{params["type"].inspect}" }
      send(action)
    end

    private

    # Seconds since the epoch, from the widget's milliseconds.
    def at = params["at"] ? params["at"] / 1000.0 : Time.now.to_f

    def attempt = Attempt.find(params.fetch("attempt"))
    def view = PassageView.find_by(attempt_id: params.fetch("attempt"), seq: params.fetch("seq"))

    def start
      return if Attempt.find_by(id: params.fetch("attempt"))
      Attempt.create(id: params.fetch("attempt"), site: params.fetch("site"),
                     label: params["label"] || params["site"], started_at: at)
    end

    def passage
      passage = Passage.record(text: params.fetch("text"), source: params["source"], url: params["url"], at: at)
      PassageView.create({ attempt_id: params.fetch("attempt"), seq: params.fetch("seq"), passage_id: passage.id,
                           shown_at: at }, replace: true)
    end

    def leave
      view&.update(left_at: at, chars_typed: params["chars"].to_i)
    end

    def typed
      shown = view or return
      shown.update(left_at: at, chars_typed: params["chars"].to_i, completed: 1)
      attempt.update(passage_id: shown.passage_id, typing_seconds: params["typing_ms"].to_f / 1000,
                     wpm: params["wpm"], peak_wpm: params["peak_wpm"], typos: params["typos"])
    end

    def finish
      outcome = params.fetch("outcome")
      raise ArgumentError, "unknown outcome: #{outcome}" unless Attempt::OUTCOMES.include?(outcome)
      reason = params["reason"].to_s.strip
      changes = { outcome: outcome, ended_at: at }
      changes[:reason] = reason unless reason.empty?
      attempt.update(changes)
    end

    def relock
      Attempt.awaiting_relock(params.fetch("site"))&.update(relock_at: params.fetch("relock_at").to_f)
    end

    def blocked_again
      Attempt.still_unblocked(params.fetch("site")).each { |a| a.update(blocked_again_at: at) }
    end
  end
end
