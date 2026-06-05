#  gGmbH
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 

cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(coremark)

set(ZEPHYR_PORT_DIR ${CMAKE_CURRENT_SOURCE_DIR})
set(COREMARK_DIR ${ZEPHYR_PORT_DIR}/../)

set(COREMARK_SRCS
        # core sources
        ${COREMARK_DIR}/core_list_join.c
        ${COREMARK_DIR}/core_main.c
        ${COREMARK_DIR}/core_matrix.c
        ${COREMARK_DIR}/core_state.c
        ${COREMARK_DIR}/core_util.c
        # port-specific sources
        ${ZEPHYR_PORT_DIR}/core_portme.c
)

if(CONFIG_SKADI_OS)
    create_skadi_subsystem_main(APP app SRCS ${COREMARK_SRCS} ${ZEPHYR_BASE}/subsys/timing/timing.c ${ZEPHYR_BASE}/arch/common/timing.c FPU)
    skadi_extension_add_compile_options(main -I${ZEPHYR_PORT_DIR} -I${COREMARK_DIR})
    if($ENV{ITERATIONS})
        target_compile_definitions(main_ext_llext_lib PRIVATE -DITERATIONS=$ENV{ITERATIONS})
        target_compile_definitions(main_ext_final_llext_lib PRIVATE -DITERATIONS=$ENV{ITERATIONS})
    else()
        target_compile_definitions(main_ext_llext_lib PRIVATE -DITERATIONS=0)
        target_compile_definitions(main_ext_final_llext_lib PRIVATE -DITERATIONS=0)
    endif()
else()
    target_sources(app PRIVATE ${COREMARK_SRCS})

    target_include_directories(app PRIVATE ${ZEPHYR_PORT_DIR})
    target_include_directories(app PRIVATE ${COREMARK_DIR})

    if($ENV{ITERATIONS})
        target_compile_definitions(app PRIVATE -DITERATIONS=$ENV{ITERATIONS})
    else()
        target_compile_definitions(app PRIVATE -DITERATIONS=0)
    endif()

    if($ENV{XCFLAGS})
        target_compile_options(app $ENV{XCFLAGS})
    endif()
endif()
