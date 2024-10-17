package hollow_array


HollowArray :: struct($T:typeid) {
	buffer : [dynamic]HollowArrayValue(T),
	dead_idx : [dynamic]int,
	count, id_access : int,
	__ite : int,
}
HollowArrayValue :: struct($T:typeid) {
	value:T,
	id: int,// When id < 0, the value is empty.
}

HollowArrayHandle :: struct($T:typeid) {
	hollow_array: ^HollowArray(T),
	index : int,
	id : int,
}

_HollowArrayHandle :: struct {
	hollow_array: rawptr,
	index : int,
	id : int,
}

hla_make :: proc($T: typeid, capacity:= 0, allocator:= context.allocator) -> HollowArray(T) {
	context.allocator = allocator
	hla : HollowArray(T)
	using hla
	buffer = make_dynamic_array_len_cap([dynamic]HollowArrayValue(T), 0, capacity)
	dead_idx = make([dynamic]int)
	return hla
}
hla_delete :: proc(using hla: ^HollowArray($T)) {
	delete(buffer)
	delete(dead_idx)
	hla^ = {}
}
hla_clear :: proc(using hla: ^HollowArray($T)) {
	clear(&buffer)
	clear(&dead_idx)
	count, id_access = 0,0
}

hla_append :: proc(using hla : ^HollowArray($T), elem: T) -> HollowArrayHandle(T) {
	index : int
	obj : ^HollowArrayValue(T)
	if len(dead_idx) > 0 {
		index = pop(&dead_idx)
		obj = &buffer[index]		
	} else {
		append(&buffer, HollowArrayValue(T){})
		index = len(buffer) - 1
		obj = &buffer[index]
	}
	obj.value = elem
	obj.id = id_access
	id_access += 1
	count += 1
	return {
		hla,
		index,
		obj.id,
	}
}

hla_remove :: proc {
	hla_remove_index,
	hla_remove_handle,
}
hla_remove_index :: proc(using hla : ^HollowArray($T), buffer_index: int) {
	if buffer_index >= len(hla.buffer) do return
	ptr := &hla.buffer[buffer_index]
	if ptr.id >= 0 {
		ptr.id = -1
		count -= 1
		append(&dead_idx, buffer_index)
	}
}
hla_remove_handle :: proc(using handle: HollowArrayHandle($T)) {
	using handle.hollow_array
	if index >= len(buffer) do return
	ptr := &buffer[index]
	if ptr.id >= 0 && ptr.id == id {
		ptr.id = -1
		count -= 1
		append(&dead_idx, index)
	}
}

hla_get_value :: proc(using handle: HollowArrayHandle($T)) -> (T, bool) #optional_ok {
	if hollow_array == nil do return {}, false
	using hollow_array
	v := buffer[index]
	if v.id != id do return {}, false
	return v.value, true
}
hla_get_pointer :: proc(using handle: HollowArrayHandle($T)) -> (^T, bool) #optional_ok {
	if hollow_array == nil do return nil, false
	using hollow_array
	v := &buffer[index]
	if v.id != id do return nil, false
	return &v.value, true
}

// thread unsafe
hla_ite :: proc(using hla: ^HollowArray($T), using iterator: ^HollowArrayIterator) -> (^T, bool) {
	assert(iterator!=nil, "HollowArray: No iterator.")
	if count == 0 do return nil, false
	if next_buffer_idx == 0 do next_alive_idx = -1

	for i in cast(int)next_buffer_idx..<len(hla.buffer) {
		v := &hla.buffer[i]
		next_buffer_idx += 1
		if v.id < 0 do continue
		next_alive_idx += 1
		buffer_idx = next_buffer_idx-1
		alive_idx = next_alive_idx-1
		return &v.value, true
	}
	return nil, false
}

ite_alive_hvalue :: proc(using hla: ^HollowArray($T), index: ^int) -> (^HollowArrayValue(T), bool) {
	if count == 0 {
		index^ = 0
		return {}, false
	}
	if index^ >= len(hla.buffer) { 
		index^ = 0
		return {}, false 
	}
	for ; index^ < len(hla.buffer); index^ = index^ + 1 {
		v := &hla.buffer[index^]
		if v.id < 0 do continue
		index^ = index^ + 1
		return v, true
	}
	index^ = 0
	return {}, false
}
ite_alive_value :: proc(using hla: ^HollowArray($T), index: ^int) -> (T, bool) {
	res, ok := ite_alive_hvalue(hla, index)
	if ok {
		return res.value, true
	}
	return nil, false
}
ite_alive_ptr :: proc(using hla: ^HollowArray($T), index: ^int) -> (^T, bool) {
	res, ok := ite_alive_hvalue(hla, index)
	if ok {
		return &res.value, true
	}
	return nil, false
}
ite_alive_handle :: proc(using hla: ^HollowArray($T), index: ^int) -> (HollowArrayHandle(T), bool) {
	res, ok := ite_alive_hvalue(hla, index)
	if ok {
		return {
			hla,
			index^-1,
			res.id
		}, true
	}
	return {}, false
}
ite_alive_ptr_handle :: proc(using hla: ^HollowArray($T), index: ^int) -> (^T, HollowArrayHandle(T), bool) {
	handle, ok := ite_alive_handle(hla, index)
	if ok {
		return hla_get_pointer(handle), handle, true
	}
	return nil, {}, false
}

ites_alive_hvalue :: proc(using hla: ^HollowArray($T)) -> (^HollowArrayValue(T), bool) {
	return ite_alive_hvalue(hla, &hla.__ite)
}
ites_alive_value :: proc(using hla: ^HollowArray($T)) -> (T, bool) {
	return ite_alive_value(hla, &hla.__ite)
}
ites_alive_ptr :: proc(using hla: ^HollowArray($T)) -> (^T, bool) {
	return ite_alive_ptr(hla, &hla.__ite)
}
ites_alive_handle :: proc(using hla: ^HollowArray($T)) -> (HollowArrayHandle(T), bool) {
	return ite_alive_handle(hla, &hla.__ite)
}

HollowArrayIterator :: struct {
	next_buffer_idx, next_alive_idx : int,
	buffer_idx, alive_idx : int,
}
