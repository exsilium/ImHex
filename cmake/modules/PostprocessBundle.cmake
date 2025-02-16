# Adapted from the Dolphin project: https://dolphin-emu.org/
# This module can be used in two different ways.
#
# When invoked as `cmake -P PostprocessBundle.cmake`, it fixes up an
# application folder to be standalone. It bundles all required libraries from
# the system and fixes up library IDs. Any additional shared libraries, like
# plugins, that are found under Contents/MacOS/ will be made standalone as well.
#
# When called with `include(PostprocessBundle)`, it defines a helper
# function `postprocess_bundle` that sets up the command form of the
# module as a post-build step.

if(CMAKE_GENERATOR)
	# Being called as include(PostprocessBundle), so define a helper function.
	set(_POSTPROCESS_BUNDLE_MODULE_LOCATION "${CMAKE_CURRENT_LIST_FILE}")
	function(postprocess_bundle out_target in_target)
		add_custom_command(TARGET ${out_target} POST_BUILD
			COMMAND ${CMAKE_COMMAND} -DBUNDLE_PATH="$<TARGET_FILE_DIR:${in_target}>/../.."
				-DCODE_SIGN_CERTIFICATE_ID="${CODE_SIGN_CERTIFICATE_ID}"
				-DEXTRA_BUNDLE_LIBRARY_PATHS="${EXTRA_BUNDLE_LIBRARY_PATHS}"
				-P "${_POSTPROCESS_BUNDLE_MODULE_LOCATION}"
		)
	endfunction()
	return()
endif()

# IMHEX PATCH BEGIN
# The function defined above doesn't keep in mind that if we are cross-compiling to MacOS, APPLE must be 1,
# so we force it here (where else would this script be run anyway ? This seems to be MacOS-specific code)
SET(APPLE 1)
# IMHEX PATCHE END

get_filename_component(BUNDLE_PATH "${BUNDLE_PATH}" ABSOLUTE)
message(STATUS "Fixing up application bundle: ${BUNDLE_PATH}")


# Make sure to fix up any included ImHex plugin.
file(GLOB_RECURSE plugins "${BUNDLE_PATH}/Contents/MacOS/plugins/*.hexplug")
file(GLOB_RECURSE plugin_libs "${BUNDLE_PATH}/Contents/MacOS/plugins/*.hexpluglib")


# BundleUtilities doesn't support DYLD_FALLBACK_LIBRARY_PATH behavior, which
# makes it sometimes break on libraries that do weird things with @rpath. Specify
# equivalent search directories until https://gitlab.kitware.com/cmake/cmake/issues/16625
# is fixed and in our minimum CMake version.
set(extra_dirs "/usr/local/lib" "/lib" "/usr/lib" ${EXTRA_BUNDLE_LIBRARY_PATHS} "${BUNDLE_PATH}/Contents/MacOS/plugins")
message(STATUS "Fixing up application bundle: ${extra_dirs}")

# BundleUtilities is overly verbose, so disable most of its messages
#function(message)
#	if(NOT ARGV MATCHES "^STATUS;")
#		_message(${ARGV})
#	endif()
#endfunction()

include(BundleUtilities)
set(BU_CHMOD_BUNDLE_ITEMS ON)

fixup_bundle("${BUNDLE_PATH}" "${plugins}" "${extra_dirs}")

if (CODE_SIGN_CERTIFICATE_ID)
	# Hack around Apple Silicon signing bugs by copying the real app, signing it and moving it back.
	# IMPORTANT: DON'T USE ${CMAKE_COMMAND} -E copy_directory HERE (this follow symbolic links).
	execute_process(COMMAND cp -R "${BUNDLE_PATH}" "${BUNDLE_PATH}.temp")
	execute_process(COMMAND codesign --deep --force --sign "${CODE_SIGN_CERTIFICATE_ID}" "${BUNDLE_PATH}.temp")
	execute_process(COMMAND ${CMAKE_COMMAND} -E remove_directory "${BUNDLE_PATH}")
	execute_process(COMMAND ${CMAKE_COMMAND} -E rename "${BUNDLE_PATH}.temp" "${BUNDLE_PATH}")
endif()

# Add a necessary rpath to the imhex binary
get_bundle_main_executable("${BUNDLE_PATH}" IMHEX_EXECUTABLE)