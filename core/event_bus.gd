extends RefCounted
## Transaction-local notifications; listeners only mutate the candidate state.
signal domain_event(candidate: Dictionary, target_id: Variant)

func publish(candidate: Dictionary, target_id: Variant) -> void:
	domain_event.emit(candidate,target_id)
