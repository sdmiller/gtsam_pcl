# Build macros for using tests

enable_testing()

# Enable make check (http://www.cmake.org/Wiki/CMakeEmulateMakeCheck)
add_custom_target(check COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure)
add_custom_target(timing)

# Add option for combining unit tests
if(MSVC)
	option(GTSAM_SINGLE_TEST_EXE "Combine unit tests into single executable (faster compile)" ON)
else()
	option(GTSAM_SINGLE_TEST_EXE "Combine unit tests into single executable (faster compile)" OFF)
endif()

# Macro for adding categorized tests in a "tests" folder, with 
# optional exclusion of tests and convenience library linking options
#  
# By default, all tests are linked with CppUnitLite and boost
# Arguments: 
#   - subdir    The name of the category for this test
#   - local_libs  A list of convenience libraries to use (if GTSAM_BUILD_CONVENIENCE_LIBRARIES is true)
#   - full_libs   The main library to link against if not using convenience libraries
#   - excluded_tests  A list of test files that should not be compiled - use for debugging 
function(gtsam_add_subdir_tests subdir local_libs full_libs excluded_tests)
    # Subdirectory target for tests
    add_custom_target(check.${subdir} COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure)
    set(is_test TRUE)
    
	# Link with CppUnitLite - pulled from gtsam installation
	list(APPEND local_libs CppUnitLite)
	list(APPEND full_libs CppUnitLite)

    # Build grouped tests
    gtsam_add_grouped_scripts("${subdir}"               # Use subdirectory as group label
    "tests/test*.cpp" check "Test"                      # Standard for all tests
    "${local_libs}"
    "${full_libs}" "${excluded_tests}"  # Pass in linking and exclusion lists
    ${is_test})                                         # Set all as tests
endfunction()

# Macro for adding categorized timing scripts in a "tests" folder, with 
# optional exclusion of tests and convenience library linking options
#  
# By default, all tests are linked with boost
# Arguments: 
#   - subdir    The name of the category for this timing script
#   - local_libs  A list of convenience libraries to use (if GTSAM_BUILD_CONVENIENCE_LIBRARIES is true)
#   - full_libs   The main library to link against if not using convenience libraries
#   - excluded_srcs  A list of timing files that should not be compiled - use for debugging 
macro(gtsam_add_subdir_timing subdir local_libs full_libs excluded_srcs)
    # Subdirectory target for timing - does not actually execute the scripts
    add_custom_target(timing.${subdir})
    set(is_test FALSE)

    # Build grouped benchmarks
    gtsam_add_grouped_scripts("${subdir}"               # Use subdirectory as group label
    "tests/time*.cpp" timing "Timing Benchmark"         # Standard for all timing scripts
    "${local_libs}" "${full_libs}" "${excluded_srcs}"   # Pass in linking and exclusion lists
    ${is_test})                                         # Treat as not a test
endmacro()

# Macro for adding executables matching a pattern - builds one executable for
# each file matching the pattern.  These exectuables are automatically linked
# with boost.
# Arguments:
#   - pattern    The glob pattern to match source files
#   - local_libs A list of convenience libraries to use (if GTSAM_BUILD_CONVENIENCE_LIBRARIES is true)
#   - full_libs  The main library to link against if not using convenience libraries
#   - excluded_srcs  A list of timing files that should not be compiled - use for debugging
function(gtsam_add_executables pattern local_libs full_libs excluded_srcs)
    set(is_test FALSE)
    
    if(NOT excluded_srcs)
        set(excluded_srcs "")
    endif()
    
    # Build executables
    gtsam_add_grouped_scripts("" "${pattern}" "" "Executable" "${local_libs}" "${full_libs}" "${excluded_srcs}" ${is_test})
endfunction()

# General-purpose script for adding tests with categories and linking options
macro(gtsam_add_grouped_scripts group pattern target_prefix pretty_prefix_name local_libs full_libs excluded_srcs is_test) 
    # Get all script files
    set(script_srcs "")
    foreach(one_pattern ${pattern})
        file(GLOB one_script_srcs "${one_pattern}")
        list(APPEND script_srcs "${one_script_srcs}")
    endforeach()

    # Remove excluded scripts from the list
    set(exclusions "") # Need to copy out exclusion list for logic to work
    foreach(one_exclusion ${excluded_srcs})
        file(GLOB one_exclusion_srcs "${one_exclusion}")
        list(APPEND exclusions "${one_exclusion_srcs}")
    endforeach()
    if(exclusions)
    	list(REMOVE_ITEM script_srcs ${exclusions})
    endif(exclusions)
    
    # Add targets and dependencies for each script
    if(NOT "${group}" STREQUAL "")
        message(STATUS "Adding ${pretty_prefix_name}s in ${group}")
    endif()
	
	# Create exe's for each script, unless we're in SINGLE_TEST_EXE mode
	if(NOT is_test OR NOT GTSAM_SINGLE_TEST_EXE)
		foreach(script_src ${script_srcs})
			get_filename_component(script_base ${script_src} NAME_WE)
			if (script_base) # Check for null filenames
				set( script_bin ${script_base} )
				message(STATUS "Adding ${pretty_prefix_name} ${script_bin}") 
				add_executable(${script_bin} ${script_src})
				if(NOT "${target_prefix}" STREQUAL "")
					if(NOT "${group}" STREQUAL "")
						add_dependencies(${target_prefix}.${group} ${script_bin})
					endif()
					add_dependencies(${target_prefix} ${script_bin})
				endif()
				
				# Add TOPSRCDIR
				set_property(SOURCE ${script_src} APPEND PROPERTY COMPILE_DEFINITIONS "TOPSRCDIR=\"${CMAKE_SOURCE_DIR}\"")

				# Disable building during make all/install
				if (GTSAM_DISABLE_TESTS_ON_INSTALL)
					set_target_properties(${script_bin} PROPERTIES EXCLUDE_FROM_ALL ON)
				endif()
				
				if (is_test)
					add_test(${script_base} ${EXECUTABLE_OUTPUT_PATH}/${script_bin} )
				endif()
				
				# Linking and dependendencies
				if (GTSAM_BUILD_CONVENIENCE_LIBRARIES)
					target_link_libraries(${script_bin} ${local_libs} ${GTSAM_BOOST_LIBRARIES})
				else()
					target_link_libraries(${script_bin} ${GTSAM_BOOST_LIBRARIES} ${full_libs})
				endif()
				
				# Add .run target
				if(NOT MSVC)
				  add_custom_target(${script_bin}.run ${EXECUTABLE_OUTPUT_PATH}${script_bin} ${ARGN})
				endif()
				
				# Set up Visual Studio folder if a unit test
				if(is_test AND MSVC)
				  set_property(TARGET ${script_bin} PROPERTY FOLDER "Unit Tests")
				elseif(MSVC)
				  set_property(TARGET ${script_bin} PROPERTY FOLDER "Executables")
				endif()
			endif()
		endforeach(script_src)
		
		if(MSVC)
			source_group("" FILES ${script_srcs})
		endif()
	else()
		# Create single unit test exe from all test scripts
		set(${script_bin} ${target_prefix}_${group}_prog)
		add_executable(${target_prefix}_${group}_prog ${script_srcs})
		if (GTSAM_BUILD_CONVENIENCE_LIBRARIES)
			target_link_libraries(${target_prefix}_${group}_prog ${local_libs} ${Boost_LIBRARIES})
		else()
			target_link_libraries(${target_prefix}_${group}_prog ${Boost_LIBRARIES} ${full_libs})
		endif()
		
		# Only have a main function in one script
		set(rest_script_srcs ${script_srcs})
		list(REMOVE_AT rest_script_srcs 0)
		set_property(SOURCE ${rest_script_srcs} APPEND PROPERTY COMPILE_DEFINITIONS "main=static no_main")
			
		# Add TOPSRCDIR
		set_property(SOURCE ${script_srcs} APPEND PROPERTY COMPILE_DEFINITIONS "TOPSRCDIR=\"${CMAKE_SOURCE_DIR}\"")
			
		# Add test
		add_dependencies(${target_prefix}.${group} ${target_prefix}_${group}_prog)
		add_dependencies(${target_prefix} ${target_prefix}_${group}_prog)
		add_test(${target_prefix}.${group} ${EXECUTABLE_OUTPUT_PATH}/${target_prefix}_${group}_prog)
		
		# Disable building during make all/install
		if (GTSAM_DISABLE_TESTS_ON_INSTALL)
			set_target_properties(${target_prefix}_${group}_prog PROPERTIES EXCLUDE_FROM_ALL ON)
		endif()
		
		# Set up Visual Studio folders
		if(MSVC)
			set_property(TARGET ${target_prefix}_${group}_prog PROPERTY FOLDER "Unit Tests")
			source_group("" FILES ${script_srcs})
		endif()
	endif()
endmacro()
