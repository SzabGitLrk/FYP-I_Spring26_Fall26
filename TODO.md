# Bus Tracking Screen Bug Fixes - TODO

## Issues Fixed:

### 1. ✅ Undeclared `_selectedStopIndex` variable
- **Location**: Lines 63 and 370
- **Problem**: Used but never declared as a class member
- **Fix**: Added `int? _selectedStopIndex;` to the class fields

### 2. ✅ Incorrect setState usage (line 60-63)
- **Problem**: `var _selectedStopIndex = i;` creates a local variable instead of updating class field
- **Fix**: Removed the `var` keyword to assign to the class field `_selectedStopIndex = i;`

### 3. ✅ Unused `_showAllBuses` variable (line 40)
- **Fix**: Removed the unused variable

### 4. ✅ Invalid `Icons.landmark` (line 317)
- **Problem**: `Icons.landmark` doesn't exist in Flutter's Material Icons
- **Fix**: Changed to `Icons.location_city`

### 5. ✅ Invalid const PatternItem (line 103)
- **Problem**: `PatternItem.dash()` and `PatternItem.gap()` cannot be used in const context
- **Fix**: Removed `const` keyword from the patterns list

## Status: COMPLETED ✅

