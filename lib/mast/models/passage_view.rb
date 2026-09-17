module Mast
  # A passage on screen during an attempt: the seq-th one shown, how far the
  # typing got before it was swapped or the attempt ended, and whether it was
  # typed out in full.
  class PassageView < Record
    primary_key :attempt_id, :seq

    def completed? = completed.to_i == 1
    def attempt = Attempt.find(attempt_id)
    def passage = Passage.find(passage_id)
  end
end
