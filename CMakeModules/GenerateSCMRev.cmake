# Gets a UTC timstamp and sets the provided variable to it
function(get_timestamp _var)
    string(TIMESTAMP timestamp UTC)
    set(${_var} "${timestamp}" PARENT_SCOPE)
endfunction()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/CMakeModules")
list(APPEND CMAKE_MODULE_PATH "${SRC_DIR}/externals/cmake-modules")

# Find the package here with the known path so that the GetGit commands can find it as well
find_package(Git QUIET PATHS "${GIT_EXECUTABLE}")

# GetGitRevisionDescription
# - Returns a version string from Git
#
# These functions force a re-configure on each git commit so that you can
# trust the values of the variables in your build system.
#
#  get_git_head_revision(<refspecvar> <hashvar> [<additional arguments to git describe> ...])
#
# Returns the refspec and sha hash of the current head revision
#
#  git_describe(<var> [<additional arguments to git describe> ...])
#
# Returns the results of git describe on the source tree, and adjusting
# the output so that it tests false if an error occurs.
#
#  git_get_exact_tag(<var> [<additional arguments to git describe> ...])
#
# Returns the results of git describe --exact-match on the source tree,
# and adjusting the output so that it tests false if there was no exact
# matching tag.
#
# Requires CMake 2.6 or newer (uses the 'function' command)
#
# Original Author:
# 2009-2010 Ryan Pavlik <rpavlik@iastate.edu> <abiryan@ryand.net>
# http://academic.cleardefinition.com
# Iowa State University HCI Graduate Program/VRAC
#
# Copyright Iowa State University 2009-2010.
# Distributed under the Boost Software License, Version 1.0.
# (See accompanying file LICENSE_1_0.txt or copy at
# http://www.boost.org/LICENSE_1_0.txt)

if(__get_git_revision_description)
	return()
endif()
set(__get_git_revision_description YES)

# We must run the following at "include" time, not at function call time,
# to find the path to this module rather than the path to a calling list file
get_filename_component(_gitdescmoddir ${CMAKE_CURRENT_LIST_FILE} PATH)

function(get_git_head_revision _refspecvar _hashvar)
	set(GIT_PARENT_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
	set(GIT_DIR "${GIT_PARENT_DIR}/.git")
	while(NOT EXISTS "${GIT_DIR}")	# .git dir not found, search parent directories
		set(GIT_PREVIOUS_PARENT "${GIT_PARENT_DIR}")
		get_filename_component(GIT_PARENT_DIR ${GIT_PARENT_DIR} PATH)
		if(GIT_PARENT_DIR STREQUAL GIT_PREVIOUS_PARENT)
			# We have reached the root directory, we are not in git
			set(${_refspecvar} "GITDIR-NOTFOUND" PARENT_SCOPE)
			set(${_hashvar} "GITDIR-NOTFOUND" PARENT_SCOPE)
			return()
		endif()
		set(GIT_DIR "${GIT_PARENT_DIR}/.git")
	endwhile()
	# check if this is a submodule
	if(NOT IS_DIRECTORY ${GIT_DIR})
		file(READ ${GIT_DIR} submodule)
		string(REGEX REPLACE "gitdir: (.*)\n$" "\\1" GIT_DIR_RELATIVE ${submodule})
		get_filename_component(SUBMODULE_DIR ${GIT_DIR} PATH)
		get_filename_component(GIT_DIR ${SUBMODULE_DIR}/${GIT_DIR_RELATIVE} ABSOLUTE)
	endif()
	set(GIT_DATA "${CMAKE_CURRENT_BINARY_DIR}/CMakeFiles/git-data")
	if(NOT EXISTS "${GIT_DATA}")
		file(MAKE_DIRECTORY "${GIT_DATA}")
	endif()

	if(NOT EXISTS "${GIT_DIR}/HEAD")
		return()
	endif()
	set(HEAD_FILE "${GIT_DATA}/HEAD")
	configure_file("${GIT_DIR}/HEAD" "${HEAD_FILE}" COPYONLY)

	configure_file("${_gitdescmoddir}/GetGitRevisionDescription.cmake.in"
		"${GIT_DATA}/grabRef.cmake"
		@ONLY)
	include("${GIT_DATA}/grabRef.cmake")

	set(${_refspecvar} "${HEAD_REF}" PARENT_SCOPE)
	set(${_hashvar} "${HEAD_HASH}" PARENT_SCOPE)
endfunction()

function(git_branch_name _var)
	if(NOT GIT_FOUND)
		find_package(Git QUIET)
	endif()

	if(NOT GIT_FOUND)
		set(${_var} "GIT-NOTFOUND" PARENT_SCOPE)
		return()
	endif()

	execute_process(COMMAND
		"${GIT_EXECUTABLE}"
		rev-parse --abbrev-ref HEAD
		WORKING_DIRECTORY
		"${CMAKE_SOURCE_DIR}"
		RESULT_VARIABLE
		res
		OUTPUT_VARIABLE
		out
		ERROR_QUIET
		OUTPUT_STRIP_TRAILING_WHITESPACE)
	if(NOT res EQUAL 0)
		set(out "${out}-${res}-NOTFOUND")
	endif()

	set(${_var} "${out}" PARENT_SCOPE)
endfunction()

function(git_describe _var)
	if(NOT GIT_FOUND)
		find_package(Git QUIET)
	endif()
	#get_git_head_revision(refspec hash)
	if(NOT GIT_FOUND)
		set(${_var} "GIT-NOTFOUND" PARENT_SCOPE)
		return()
	endif()
	#if(NOT hash)
	#	set(${_var} "HEAD-HASH-NOTFOUND" PARENT_SCOPE)
	#	return()
	#endif()

	# TODO sanitize
	#if((${ARGN}" MATCHES "&&") OR
	#	(ARGN MATCHES "||") OR
	#	(ARGN MATCHES "\\;"))
	#	message("Please report the following error to the project!")
	#	message(FATAL_ERROR "Looks like someone's doing something nefarious with git_describe! Passed arguments ${ARGN}")
	#endif()

	#message(STATUS "Arguments to execute_process: ${ARGN}")

	execute_process(COMMAND
		"${GIT_EXECUTABLE}"
		describe
		${hash}
		${ARGN}
		WORKING_DIRECTORY
		"${CMAKE_SOURCE_DIR}"
		RESULT_VARIABLE
		res
		OUTPUT_VARIABLE
		out
		ERROR_QUIET
		OUTPUT_STRIP_TRAILING_WHITESPACE)
	if(NOT res EQUAL 0)
		set(out "${out}-${res}-NOTFOUND")
	endif()

	set(${_var} "${out}" PARENT_SCOPE)
endfunction()

function(git_get_exact_tag _var)
	git_describe(out --exact-match ${ARGN})
	set(${_var} "${out}" PARENT_SCOPE)
endfunction()
# generate git/build information
get_git_head_revision(GIT_REF_SPEC GIT_REV)
git_describe(GIT_DESC --always --long --dirty)
git_branch_name(GIT_BRANCH)
get_timestamp(BUILD_DATE)

# Generate cpp with Git revision from template
# Also if this is a CI build, add the build name (ie: Nightly, Canary) to the scm_rev file as well
set(REPO_NAME "")
set(BUILD_VERSION "0")
if (BUILD_REPOSITORY)
  # regex capture the string nightly or canary into CMAKE_MATCH_1
  string(REGEX MATCH "yuzu-emu/yuzu-?(.*)" OUTVAR ${BUILD_REPOSITORY})
  if ("${CMAKE_MATCH_COUNT}" GREATER 0)
    # capitalize the first letter of each word in the repo name.
    string(REPLACE "-" ";" REPO_NAME_LIST ${CMAKE_MATCH_1})
    foreach(WORD ${REPO_NAME_LIST})
      string(SUBSTRING ${WORD} 0 1 FIRST_LETTER)
      string(SUBSTRING ${WORD} 1 -1 REMAINDER)
      string(TOUPPER ${FIRST_LETTER} FIRST_LETTER)
      set(REPO_NAME "${REPO_NAME}${FIRST_LETTER}${REMAINDER}")
    endforeach()
    if (BUILD_TAG)
      string(REGEX MATCH "${CMAKE_MATCH_1}-([0-9]+)" OUTVAR ${BUILD_TAG})
      if (${CMAKE_MATCH_COUNT} GREATER 0)
        set(BUILD_VERSION ${CMAKE_MATCH_1})
      endif()
      if (BUILD_VERSION)
        # This leaves a trailing space on the last word, but we actually want that
        # because of how it's styled in the title bar.
        set(BUILD_FULLNAME "${REPO_NAME} ${BUILD_VERSION} ")
      else()
        set(BUILD_FULLNAME "")
      endif()
    endif()
  endif()
endif()

# The variable SRC_DIR must be passed into the script (since it uses the current build directory for all values of CMAKE_*_DIR)
set(VIDEO_CORE "${SRC_DIR}/src/video_core")
set(HASH_FILES
    "${VIDEO_CORE}/renderer_opengl/gl_shader_cache.cpp"
    "${VIDEO_CORE}/renderer_opengl/gl_shader_cache.h"
    "${VIDEO_CORE}/renderer_opengl/gl_shader_decompiler.cpp"
    "${VIDEO_CORE}/renderer_opengl/gl_shader_decompiler.h"
    "${VIDEO_CORE}/renderer_opengl/gl_shader_disk_cache.cpp"
    "${VIDEO_CORE}/renderer_opengl/gl_shader_disk_cache.h"
    "${VIDEO_CORE}/shader/decode/arithmetic.cpp"
    "${VIDEO_CORE}/shader/decode/arithmetic_half.cpp"
    "${VIDEO_CORE}/shader/decode/arithmetic_half_immediate.cpp"
    "${VIDEO_CORE}/shader/decode/arithmetic_immediate.cpp"
    "${VIDEO_CORE}/shader/decode/arithmetic_integer.cpp"
    "${VIDEO_CORE}/shader/decode/arithmetic_integer_immediate.cpp"
    "${VIDEO_CORE}/shader/decode/bfe.cpp"
    "${VIDEO_CORE}/shader/decode/bfi.cpp"
    "${VIDEO_CORE}/shader/decode/conversion.cpp"
    "${VIDEO_CORE}/shader/decode/ffma.cpp"
    "${VIDEO_CORE}/shader/decode/float_set.cpp"
    "${VIDEO_CORE}/shader/decode/float_set_predicate.cpp"
    "${VIDEO_CORE}/shader/decode/half_set.cpp"
    "${VIDEO_CORE}/shader/decode/half_set_predicate.cpp"
    "${VIDEO_CORE}/shader/decode/hfma2.cpp"
    "${VIDEO_CORE}/shader/decode/image.cpp"
    "${VIDEO_CORE}/shader/decode/integer_set.cpp"
    "${VIDEO_CORE}/shader/decode/integer_set_predicate.cpp"
    "${VIDEO_CORE}/shader/decode/memory.cpp"
    "${VIDEO_CORE}/shader/decode/texture.cpp"
    "${VIDEO_CORE}/shader/decode/other.cpp"
    "${VIDEO_CORE}/shader/decode/predicate_set_predicate.cpp"
    "${VIDEO_CORE}/shader/decode/predicate_set_register.cpp"
    "${VIDEO_CORE}/shader/decode/register_set_predicate.cpp"
    "${VIDEO_CORE}/shader/decode/shift.cpp"
    "${VIDEO_CORE}/shader/decode/video.cpp"
    "${VIDEO_CORE}/shader/decode/warp.cpp"
    "${VIDEO_CORE}/shader/decode/xmad.cpp"
    "${VIDEO_CORE}/shader/ast.cpp"
    "${VIDEO_CORE}/shader/ast.h"
    "${VIDEO_CORE}/shader/compiler_settings.cpp"
    "${VIDEO_CORE}/shader/compiler_settings.h"
    "${VIDEO_CORE}/shader/control_flow.cpp"
    "${VIDEO_CORE}/shader/control_flow.h"
    "${VIDEO_CORE}/shader/decode.cpp"
    "${VIDEO_CORE}/shader/expr.cpp"
    "${VIDEO_CORE}/shader/expr.h"
    "${VIDEO_CORE}/shader/node.h"
    "${VIDEO_CORE}/shader/node_helper.cpp"
    "${VIDEO_CORE}/shader/node_helper.h"
    "${VIDEO_CORE}/shader/registry.cpp"
    "${VIDEO_CORE}/shader/registry.h"
    "${VIDEO_CORE}/shader/shader_ir.cpp"
    "${VIDEO_CORE}/shader/shader_ir.h"
    "${VIDEO_CORE}/shader/track.cpp"
    "${VIDEO_CORE}/shader/transform_feedback.cpp"
    "${VIDEO_CORE}/shader/transform_feedback.h"
)
set(COMBINED "")
foreach (F IN LISTS HASH_FILES)
    file(READ ${F} TMP)
    set(COMBINED "${COMBINED}${TMP}")
endforeach()
string(MD5 SHADER_CACHE_VERSION "${COMBINED}")
configure_file("${SRC_DIR}/src/common/scm_rev.cpp.in" "scm_rev.cpp" @ONLY)
