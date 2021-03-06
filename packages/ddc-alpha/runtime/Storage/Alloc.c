
#include "../Runtime.h"

#include <stdlib.h>
#include <stdio.h>


// Initialise the allocation system and allocate the heap.
void	_allocInit (size_t heapSize)
{
	_ddcHeapBase		= malloc (heapSize);
	_ddcHeapPtr		= _ddcHeapBase;
	_ddcHeapMax		= _ddcHeapBase + heapSize - 1;

	_ddcHeapBackBase	= malloc (heapSize);
	_ddcHeapBackPtr		= _ddcHeapBackBase;
	_ddcHeapBackMax		= _ddcHeapBackBase + heapSize - 1;
}


// Perform a garbage collection.
void	_allocCollect
		(size_t byteCount)	// How much space must be left over after the collection.
					// If we don't get at least this much back then the RTS will panic.
{
	// Check how much data is in the heap before collection.
	Word64	heapUsageStart	= _ddcHeapPtr - _ddcHeapBase;

#if 	_DDC_PROFILE_GC
	_ddcProfileMutatorEnd();
	_ddcProfileCollectorStart();
#endif
	_PROFILE_GC (allocBytes	+= heapUsageStart - _ddcProfile ->gc.lastCompactionSize);

	// Copy out the live data to the new heap.
	_collectHeap
		( _ddcHeapBase
		, _ddcHeapPtr
		, _ddcHeapMax
		, _ddcHeapBackBase
		, &_ddcHeapBackPtr);

#if 	_DDC_PROFILE_GC
	_ddcProfileCollectorEnd();
	_ddcProfileMutatorStart();
#endif

	// Flip the from and to space buffers
	Word8*	tmp;
	tmp			= _ddcHeapBase;
	_ddcHeapBase		= _ddcHeapBackBase;
	_ddcHeapBackBase	= tmp;

	tmp			= _ddcHeapPtr;
	_ddcHeapPtr		= _ddcHeapBackPtr;
	_ddcHeapBackPtr		= tmp;

	tmp			= _ddcHeapMax;
	_ddcHeapMax		= _ddcHeapBackMax;
	_ddcHeapBackMax		= tmp;

	// Check how much data is in the heap after collection.
	Word64 heapUsageEnd	= _ddcHeapPtr - _ddcHeapBase;
	_PROFILE_GC (lastCompactionSize = heapUsageEnd);

	// If we haven't recovered enough space, then the allocation that triggered this
	// 	collection won't be able to complete, so we're screwed.
	// TODO: instead of just panicing we should grow the heap.
	if (_ddcHeapPtr + byteCount > _ddcHeapMax)
		_panicOutOfHeap (byteCount, (Word64)(_ddcHeapMax - _ddcHeapBase + 1));
}

