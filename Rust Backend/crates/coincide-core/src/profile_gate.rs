pub const TOOL_REGISTRY: &[&str] = &["access_level_audit", "accessibility_audit", "accessibility_audit_scanner", "api_docs_coverage",
    "api_endpoint_audit", "api_surface_extract", "asset_catalog_list", "asset_catalog_manager",
    "asset_image_add", "automated_repair_engine", "autonomous_review_engine", "batch_rename_files",
    "binary_plist_converter", "binary_size_report", "build_configuration_list", "build_log_analyze",
    "build_phase_scripts_list", "build_settings_diff", "build_system_detect", "bundle_resource_auditor",
    "call_hierarchy", "cancel_worker", "carthage_cartfile_inspector", "change_impact_estimate",
    "click", "click_point", "clipboard_manager_tool", "code_comment_extract",
    "code_format", "code_generate", "code_insert", "code_lint",
    "code_metrics_analyzer", "code_multi_edit", "code_mutation_engine", "code_replace",
    "code_signing_diagnose", "code_snippet_manager", "code_summary", "color_usage_audit",
    "colorset_builder", "comment_density_report", "compiler_diagnostics_engine", "complexity_analysis",
    "concurrency_audit", "conflict_marker_scan", "context_persistence_store", "copy_file",
    "core_data_model_inspector", "count_file_lines", "crash_log_parse", "create_artifact",
    "create_directory", "create_file", "create_terminal", "csv_to_json",
    "dead_code_eliminator", "dead_code_scan", "delete_artifact", "delete_directory",
    "delete_file", "delete_worker", "dependency_graph", "dependency_licenses",
    "dependency_resolution_engine", "deprecation_usage_scan", "derived_data_locate", "device_list",
    "dir_create", "dir_delete", "dir_read", "dir_size_report",
    "disk_space_analyzer", "docc_build", "docs_generate", "docs_index_build",
    "docstring_generator", "double_click", "drag", "duplicate_code_scan",
    "edit_file", "empty_dirs_find", "entitlements_diff", "entitlements_manager",
    "entry_points_discover", "env_capture_logs", "env_info", "environment_variable_manager",
    "executable_files_scan", "execution_plan", "external_resource_gateway", "extract_code_symbols",
    "fetch_documentation", "file_append", "file_backup", "file_checksum_verifier",
    "file_compare_diff", "file_copy", "file_create", "file_delete",
    "file_hash_verify", "file_head_preview", "file_metadata", "file_move",
    "file_read", "file_rename", "file_type_breakdown", "file_write",
    "find_duplicate_files", "force_unwrap_scan", "format_json_file", "framework_linker_auditor",
    "function_size_report", "generate_file_checksum", "generate_xcodeproj", "get_desktop_state",
    "get_window_state", "git_bisect", "git_blame_inspector", "git_branch_checkout",
    "git_branch_compare", "git_branch_create", "git_branch_list", "git_branch_manager",
    "git_cherry_pick", "git_commit", "git_conflict_resolver", "git_diff",
    "git_diff_branch", "git_diff_range", "git_log", "git_log_viewer",
    "git_pr_summary", "git_pull", "git_push", "git_review_diff",
    "git_show", "git_stash_operator", "git_status", "github_repo",
    "gzip_compress_file", "gzip_decompress_file", "hotkey", "icon_generator_tool",
    "image_asset_size_report", "image_convert_format", "image_decode_base64", "image_encode_base64",
    "image_extract_metadata", "image_generate_thumbnail", "image_get_dimensions", "import_cleanup",
    "import_graph", "info_plist_audit", "intel_breakdown_task", "intel_explain_code",
    "intel_generate_tests", "intel_plan_task", "interface_simulator", "invoke_menu",
    "json_to_csv", "json_to_plist", "json_validate", "json_validator_tool",
    "launch_app", "license_header_check", "list_apps", "list_artifacts",
    "list_directory", "list_files", "list_windows", "list_workers",
    "localization_audit", "localization_manager", "localize_app", "mach_o_binary_analyzer",
    "manage_memory", "markdown_link_check", "markdown_toc_generate", "mem_clear",
    "mem_context_snapshot", "mem_delete", "mem_retrieve", "mem_store",
    "memory_leak_detector", "move_cursor", "move_file", "multi_edit_file",
    "network_security_auditor", "open_in_finder", "package_dependency_add", "package_dependency_audit",
    "package_dependency_update", "package_manifest_read", "package_manifest_validate", "patch_application_engine",
    "pbxproj_lint", "performance_benchmark", "permissions_audit", "plan-AskUser",
    "plist_edit", "plist_editor", "plist_to_json", "podfile_inspector",
    "preflight_checks", "press_key", "privacy_manifest_auditor", "process_monitor_tool",
    "project_archive", "project_build", "project_build_settings", "project_capabilities",
    "project_changelog", "project_clean", "project_diff", "project_entitlements",
    "project_info_plist", "project_restore", "project_scheme_list", "project_signing",
    "project_snapshot", "project_structure_map", "project_target_list", "project_test",
    "protocol_conformance_list", "provisioning_check", "provisioning_profile_reader", "read_artifact",
    "read_directory", "read_file", "read_terminal", "read_url_content",
    "readme_generate", "readme_locate", "recent_changes", "regex_replace_in_files",
    "repo_overview", "report_to_user", "reveal_in_finder", "reverse_analyze",
    "right_click", "run_build", "run_command", "run_tests",
    "runtime_diagnostics_engine", "safe_undo", "safe_validate_changes", "save_to_memory",
    "scheme_test_plan_list", "scroll", "search_directory", "search_files",
    "search_regex", "search_skills", "search_symbol", "search_text",
    "search_web", "secrets_scan", "security_audit_scanner", "semantic_query_engine",
    "session_export", "session_progress_report", "set_value", "set_window_frame",
    "signing_certificate_inspector", "simulator_boot", "simulator_controller", "simulator_list",
    "source_graph_builder", "spm_dependency_tree", "stale_files_report", "start_subagent",
    "string_catalog_migrator", "string_literal_audit", "strings_file_validate", "strings_localization",
    "svg_to_png", "swift_ast_inspector", "swift_concurrency_analyzer", "swift_data_schema_auditor",
    "swift_format_lint", "swift_migration_advisor", "swift_package_manager", "symbol_move_file",
    "symbol_reference_graph", "symbol_rename_project", "symlink_audit",
    "system_asset_get_metadata", "system_asset_list", "system_asset_read",
    "system_asset_search_related", "system_notification_tool",
    "take_screenshot", "tar_archive_create", "tar_archive_extract", "target_dependencies_list",
    "target_source_list", "test_coverage_report", "test_coverage_reporter", "test_data_factory",
    "test_flaky_detect", "test_log_parse", "test_run_single", "test_snapshot_manage",
    "todo_fixme_scanner", "todo_scan", "tool_capability_lookup", "tree_view",
    "type_hierarchy", "type_text", "ui_test_scaffold", "unused_imports_detector",
    "unzip_file", "use_app", "use_mcp", "use_system",
    "use_terminal", "use_workers", "verify_state", "version_control_operator",
    "view_file", "view_memory", "worker_result", "worker_status",
    "workspace_settings_read", "write_file", "write_terminal", "xcode_build_settings_inspector",
    "xcode_device_destination_finder", "xcode_scheme_manager", "xcode_toolchain_info", "xcresult_parser",
    "xctest_discovery", "yaml_parser_tool", "yaml_validate", "zip_file",
    "zoom",];

pub const READ_ONLY_DENIED_TOOLS: &[&str] = &["asset_catalog_manager", "asset_image_add", "automated_repair_engine", "batch_rename_files",
    "binary_plist_converter", "cancel_worker", "click", "click_point",
    "clipboard_manager_tool", "code_format", "code_generate", "code_insert",
    "code_multi_edit", "code_mutation_engine", "code_replace", "code_snippet_manager",
    "colorset_builder", "compiler_diagnostics_engine", "context_persistence_store", "copy_file",
    "create_artifact", "create_directory", "create_file", "create_terminal",
    "csv_to_json", "dead_code_eliminator", "delete_artifact", "delete_directory",
    "delete_file", "delete_worker", "dependency_resolution_engine", "dir_create",
    "dir_delete", "docc_build", "docs_generate", "double_click",
    "drag", "edit_file", "entitlements_manager", "env_capture_logs",
    "execution_plan", "file_append", "file_backup", "file_copy",
    "file_create", "file_delete", "file_move", "file_rename",
    "file_write", "format_json_file", "generate_xcodeproj", "git_bisect",
    "git_branch_checkout", "git_branch_create", "git_branch_manager", "git_cherry_pick",
    "git_commit", "git_conflict_resolver", "git_pull", "git_push",
    "git_stash_operator", "github_repo", "gzip_compress_file", "gzip_decompress_file", "hotkey",
    "icon_generator_tool", "image_convert_format", "image_decode_base64", "image_generate_thumbnail",
    "import_cleanup", "intel_breakdown_task", "intel_generate_tests", "intel_plan_task",
    "invoke_menu", "json_to_csv", "json_to_plist", "json_validate",
    "launch_app", "localization_manager", "localize_app", "manage_memory",
    "markdown_toc_generate", "mem_clear", "mem_context_snapshot", "mem_delete",
    "mem_store", "move_cursor", "move_file", "multi_edit_file",
    "package_dependency_add", "package_dependency_update", "patch_application_engine", "performance_benchmark",
    "plist_edit", "plist_editor", "plist_to_json", "preflight_checks",
    "press_key", "project_archive", "project_build", "project_capabilities",
    "project_clean", "project_info_plist", "project_restore", "project_snapshot",
    "project_test", "read_terminal", "readme_generate", "regex_replace_in_files",
    "report_to_user", "right_click", "run_build", "run_command",
    "run_tests", "safe_undo", "save_to_memory", "scroll",
    "session_export", "set_value", "set_window_frame", "simulator_boot",
    "simulator_controller", "start_subagent", "string_catalog_migrator", "strings_localization",
    "svg_to_png", "swift_format_lint", "swift_package_manager", "symbol_move_file",
    "symbol_rename_project", "system_notification_tool", "tar_archive_create", "tar_archive_extract",
    "test_data_factory", "test_run_single", "test_snapshot_manage", "type_text",
    "ui_test_scaffold", "unzip_file", "use_app", "use_mcp",
    "use_system", "use_terminal", "use_workers", "version_control_operator",
    "write_file", "write_terminal", "yaml_validate", "zip_file", "zoom",];

pub const APPROVAL_REQUIRED_DENIED_TOOLS: &[&str] = &["binary_size_report", "code_signing_diagnose", "compiler_diagnostics_engine", "create_terminal",
    "delete_artifact", "delete_directory", "delete_file", "delete_worker",
    "dependency_resolution_engine", "device_list", "dir_delete", "disk_space_analyzer",
    "docc_build", "file_delete", "generate_xcodeproj", "git_bisect",
    "git_branch_checkout", "git_branch_create", "git_branch_manager", "git_cherry_pick",
    "git_commit", "git_conflict_resolver", "git_pull", "git_push",
    "git_stash_operator", "github_repo", "gzip_compress_file", "gzip_decompress_file", "icon_generator_tool",
    "image_convert_format", "image_extract_metadata", "image_generate_thumbnail", "image_get_dimensions",
    "mach_o_binary_analyzer", "manage_memory", "mem_clear", "mem_delete",
    "package_dependency_audit", "package_dependency_update", "package_manifest_validate", "performance_benchmark",
    "preflight_checks", "process_monitor_tool", "project_archive", "project_build",
    "project_build_settings", "project_clean", "project_restore", "project_scheme_list",
    "project_signing", "project_snapshot", "project_target_list", "project_test",
    "provisioning_check", "provisioning_profile_reader", "reverse_analyze", "run_build",
    "run_command", "run_tests", "safe_undo", "signing_certificate_inspector",
    "simulator_boot", "simulator_controller", "simulator_list", "spm_dependency_tree",
    "svg_to_png", "swift_ast_inspector", "swift_format_lint", "swift_package_manager",
    "tar_archive_create", "tar_archive_extract", "test_coverage_report", "test_coverage_reporter",
    "test_run_single", "test_snapshot_manage", "unzip_file", "use_system",
    "use_terminal", "version_control_operator", "write_terminal", "xcode_build_settings_inspector",
    "xcode_device_destination_finder", "xcode_scheme_manager", "xcode_toolchain_info", "xcresult_parser",
    "zip_file",];

pub fn tool_denied_by_profile(profile: &str, tool: &str) -> bool {
    match profile {
        "read-only" => READ_ONLY_DENIED_TOOLS.contains(&tool),
        "approval-required" => APPROVAL_REQUIRED_DENIED_TOOLS.contains(&tool),
        "workspace-modify" | "terminal" => false,
        _ => true,
    }
}

pub fn use_app_inner_tool(action: &str) -> Option<&'static str> {
    match action {
        "list_applications" => Some("list_apps"),
        "inspect_application" | "list_windows" => Some("list_windows"),
        "launch" => Some("launch_app"),
        "inspect_ui" | "get_accessibility_tree" => Some("get_window_state"),
        "take_screenshot" => Some("get_desktop_state"),
        "click" | "activate_element" => Some("click"),
        "double_click" => Some("double_click"),
        "right_click" => Some("right_click"),
        "move_pointer" => Some("move_cursor"),
        "drag" => Some("drag"),
        "scroll" => Some("scroll"),
        "type_text" => Some("type_text"),
        "press_key" => Some("press_key"),
        "press_shortcut" => Some("hotkey"),
        "set_element_value" => Some("set_value"),
        "select_menu" => Some("invoke_menu"),
        "verify" => Some("verify_state"),
        _ => None,
    }
}

pub fn effective_allowed_tools(
    profile: &str,
    allowed_tools: Option<&[String]>,
) -> Option<Vec<String>> {
    let allowed_tools = allowed_tools?;
    Some(
        allowed_tools
            .iter()
            .filter(|tool| !tool_denied_by_profile(profile, tool))
            .cloned()
            .collect(),
    )
}

pub fn materialized_allowed_tools(
    profile: &str,
    allowed_tools: Option<&[String]>,
) -> Option<Vec<String>> {
    match allowed_tools {
        Some(allowed_tools) => effective_allowed_tools(profile, Some(allowed_tools)),
        None => match profile {
            "read-only" | "approval-required" => Some(
                TOOL_REGISTRY
                    .iter()
                    .filter(|tool| !tool_denied_by_profile(profile, tool))
                    .map(|tool| tool.to_string())
                    .collect(),
            ),
            "workspace-modify" | "terminal" => None,
            _ => Some(Vec::new()),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn deny_sets_are_sorted_deduped_and_cover_registry_tools() {
        let mut registry = TOOL_REGISTRY.to_vec();
        registry.sort_unstable();
        assert_eq!(TOOL_REGISTRY, registry.as_slice());
        assert_eq!(TOOL_REGISTRY.len(), 337);
        let mut seen = std::collections::HashSet::new();
        for tool in TOOL_REGISTRY {
            assert!(seen.insert(*tool));
        }
        for set in [READ_ONLY_DENIED_TOOLS, APPROVAL_REQUIRED_DENIED_TOOLS] {
            assert!(!set.is_empty());
            let mut sorted = set.to_vec();
            sorted.sort_unstable();
            assert_eq!(set, sorted.as_slice());
            let mut seen = std::collections::HashSet::new();
            for tool in set {
                assert!(!tool.is_empty() && !tool.contains(' '));
                assert!(seen.insert(*tool));
                assert!(
                    TOOL_REGISTRY.contains(tool),
                    "deny set names unknown tool {tool}"
                );
            }
        }
        assert_eq!(READ_ONLY_DENIED_TOOLS.len(), 150);
        assert_eq!(APPROVAL_REQUIRED_DENIED_TOOLS.len(), 86);
        assert!(READ_ONLY_DENIED_TOOLS.contains(&"git_branch_manager"));
        assert!(READ_ONLY_DENIED_TOOLS.contains(&"use_app"));
        assert!(APPROVAL_REQUIRED_DENIED_TOOLS.contains(&"git_branch_manager"));
        assert!(!READ_ONLY_DENIED_TOOLS.contains(&"read_file"));
        assert!(!APPROVAL_REQUIRED_DENIED_TOOLS.contains(&"read_file"));
        assert!(READ_ONLY_DENIED_TOOLS.contains(&"use_mcp"));
        assert!(!APPROVAL_REQUIRED_DENIED_TOOLS.contains(&"use_mcp"));
    }

    #[test]
    fn deny_sets_match_shared_profile_deny_lists_manifest() {
        let manifest = include_str!("../../../../Agents/Resources/ProfileDenyLists.json");
        let parsed: serde_json::Value =
            serde_json::from_str(manifest).expect("profile deny lists manifest parses");
        let read_only = parsed["readOnlyDenied"]
            .as_array()
            .expect("manifest carries readOnlyDenied")
            .iter()
            .map(|name| name.as_str().expect("deny entry is a string"))
            .collect::<Vec<_>>();
        let approval = parsed["approvalRequiredDenied"]
            .as_array()
            .expect("manifest carries approvalRequiredDenied")
            .iter()
            .map(|name| name.as_str().expect("deny entry is a string"))
            .collect::<Vec<_>>();
        assert_eq!(READ_ONLY_DENIED_TOOLS, read_only.as_slice());
        assert_eq!(APPROVAL_REQUIRED_DENIED_TOOLS, approval.as_slice());
    }

    #[test]
    fn unified_deny_sets_include_reconciled_tools() {
        for tool in [
            "dead_code_eliminator",
            "entitlements_manager",
            "env_capture_logs",
            "execution_plan",
            "intel_breakdown_task",
            "intel_plan_task",
            "json_to_plist",
            "mem_context_snapshot",
            "project_capabilities",
            "project_info_plist",
            "read_terminal",
            "system_notification_tool",
            "use_mcp",
            "github_repo",
            "zoom",
        ] {
            assert!(
                tool_denied_by_profile("read-only", tool),
                "{tool} must be denied for read-only"
            );
        }
        for tool in [
            "git_conflict_resolver",
            "manage_memory",
            "project_restore",
            "project_snapshot",
            "safe_undo",
            "github_repo",
        ] {
            assert!(
                tool_denied_by_profile("approval-required", tool),
                "{tool} must be denied for approval-required"
            );
        }
        assert!(
            !tool_denied_by_profile("approval-required", "zoom"),
            "zoom stays allowed for approval-required"
        );
    }

    #[test]
    fn read_only_profile_denies_write_tools() {
        for tool in [
            "write_file",
            "create_file",
            "edit_file",
            "multi_edit_file",
            "code_replace",
            "delete_file",
            "delete_directory",
            "move_file",
            "copy_file",
            "create_directory",
            "create_terminal",
            "write_terminal",
            "run_command",
            "run_build",
            "run_tests",
            "git_commit",
            "git_push",
            "git_pull",
            "git_branch_create",
            "git_branch_manager",
            "version_control_operator",
            "project_snapshot",
            "project_restore",
            "safe_undo",
            "click",
            "double_click",
            "type_text",
            "press_key",
            "launch_app",
            "use_app",
            "use_mcp",
            "use_system",
            "use_workers",
            "start_subagent",
            "cancel_worker",
            "delete_worker",
            "mem_store",
            "mem_delete",
            "mem_clear",
            "save_to_memory",
            "test_snapshot_manage",
            "clipboard_manager_tool",
            "system_notification_tool",
            "env_capture_logs",
            "asset_catalog_manager",
            "compiler_diagnostics_engine",
            "project_build",
            "zip_file",
            "tar_archive_create",
            "unzip_file",
            "svg_to_png",
            "icon_generator_tool",
            "project_capabilities",
            "project_info_plist",
            "package_dependency_update",
            "simulator_boot",
        ] {
            assert!(
                tool_denied_by_profile("read-only", tool),
                "{tool} must be denied for read-only"
            );
        }
    }

    #[test]
    fn read_only_profile_allows_read_tools() {
        for tool in [
            "read_file",
            "list_files",
            "list_directory",
            "search_files",
            "search_text",
            "search_regex",
            "git_status",
            "git_log",
            "git_diff",
            "git_show",
            "git_branch_list",
            "project_scheme_list",
            "project_target_list",
            "simulator_list",
            "disk_space_analyzer",
            "xcode_scheme_manager",
            "reverse_analyze",
            "test_coverage_report",
            "test_coverage_reporter",
            "docs_index_build",
            "environment_variable_manager",
            "get_desktop_state",
            "get_window_state",
            "list_apps",
            "list_windows",
            "verify_state",
            "take_screenshot",
            "search_web",
            "read_url_content",
            "mem_retrieve",
            "view_memory",
            "list_workers",
            "worker_result",
            "plan-AskUser",
        ] {
            assert!(
                !tool_denied_by_profile("read-only", tool),
                "{tool} must be allowed for read-only"
            );
        }
    }

    #[test]
    fn approval_required_profile_denies_terminal_git_mutating_and_delete_tools() {
        for tool in [
            "create_terminal",
            "write_terminal",
            "run_command",
            "run_build",
            "run_tests",
            "use_terminal",
            "use_system",
            "project_scheme_list",
            "project_target_list",
            "project_build_settings",
            "project_signing",
            "simulator_list",
            "device_list",
            "disk_space_analyzer",
            "image_get_dimensions",
            "image_extract_metadata",
            "image_convert_format",
            "image_generate_thumbnail",
            "gzip_compress_file",
            "gzip_decompress_file",
            "zip_file",
            "unzip_file",
            "tar_archive_create",
            "tar_archive_extract",
            "svg_to_png",
            "swift_format_lint",
            "test_coverage_report",
            "test_coverage_reporter",
            "compiler_diagnostics_engine",
            "git_commit",
            "git_push",
            "git_pull",
            "git_branch_create",
            "git_branch_checkout",
            "git_branch_manager",
            "git_cherry_pick",
            "git_stash_operator",
            "git_conflict_resolver",
            "git_bisect",
            "version_control_operator",
            "project_restore",
            "project_snapshot",
            "safe_undo",
            "delete_file",
            "file_delete",
            "delete_directory",
            "dir_delete",
            "delete_artifact",
            "delete_worker",
            "mem_delete",
            "mem_clear",
            "manage_memory",
            "test_snapshot_manage",
        ] {
            assert!(
                tool_denied_by_profile("approval-required", tool),
                "{tool} must be denied for approval-required"
            );
        }
    }

    #[test]
    fn approval_required_profile_allows_workspace_writes_and_reads() {
        for tool in [
            "write_file",
            "edit_file",
            "create_file",
            "read_file",
            "git_status",
            "git_log",
            "git_diff",
            "read_terminal",
            "use_mcp",
            "use_app",
            "project_info_plist",
            "project_capabilities",
            "click",
            "type_text",
            "mem_store",
            "use_workers",
        ] {
            assert!(
                !tool_denied_by_profile("approval-required", tool),
                "{tool} must be allowed for approval-required"
            );
        }
    }

    #[test]
    fn workspace_modify_and_terminal_profiles_impose_no_ceiling() {
        for profile in ["workspace-modify", "terminal"] {
            for tool in [
                "write_file",
                "delete_file",
                "create_terminal",
                "run_command",
                "git_commit",
                "git_push",
                "click",
                "use_mcp",
            ] {
                assert!(
                    !tool_denied_by_profile(profile, tool),
                    "{tool} must be allowed for {profile}"
                );
            }
        }
    }

    #[test]
    fn unknown_profile_fails_closed() {
        for tool in ["read_file", "write_file", "list_files"] {
            assert!(tool_denied_by_profile("bogus", tool));
            assert!(tool_denied_by_profile("", tool));
        }
    }

    #[test]
    fn use_app_inner_tool_mapping_matches_f3b() {
        assert_eq!(use_app_inner_tool("list_applications"), Some("list_apps"));
        assert_eq!(use_app_inner_tool("inspect_application"), Some("list_windows"));
        assert_eq!(use_app_inner_tool("list_windows"), Some("list_windows"));
        assert_eq!(use_app_inner_tool("launch"), Some("launch_app"));
        assert_eq!(use_app_inner_tool("inspect_ui"), Some("get_window_state"));
        assert_eq!(
            use_app_inner_tool("get_accessibility_tree"),
            Some("get_window_state")
        );
        assert_eq!(use_app_inner_tool("click"), Some("click"));
        assert_eq!(use_app_inner_tool("activate_element"), Some("click"));
        assert_eq!(use_app_inner_tool("double_click"), Some("double_click"));
        assert_eq!(use_app_inner_tool("right_click"), Some("right_click"));
        assert_eq!(use_app_inner_tool("move_pointer"), Some("move_cursor"));
        assert_eq!(use_app_inner_tool("drag"), Some("drag"));
        assert_eq!(use_app_inner_tool("scroll"), Some("scroll"));
        assert_eq!(use_app_inner_tool("type_text"), Some("type_text"));
        assert_eq!(use_app_inner_tool("press_key"), Some("press_key"));
        assert_eq!(use_app_inner_tool("press_shortcut"), Some("hotkey"));
        assert_eq!(use_app_inner_tool("set_element_value"), Some("set_value"));
        assert_eq!(use_app_inner_tool("select_menu"), Some("invoke_menu"));
        assert_eq!(use_app_inner_tool("verify"), Some("verify_state"));
        assert_eq!(use_app_inner_tool("take_screenshot"), Some("get_desktop_state"));
        assert_eq!(use_app_inner_tool("activate"), None);
        assert_eq!(use_app_inner_tool("close_application"), None);
        assert_eq!(use_app_inner_tool("no_such_action"), None);
    }

    #[test]
    fn effective_allowed_tools_narrows_lists_by_profile() {
        let tools = |names: &[&str]| {
            names
                .iter()
                .map(|name| name.to_string())
                .collect::<Vec<_>>()
        };
        assert_eq!(
            effective_allowed_tools("read-only", Some(&tools(&["read_file", "write_file"]))),
            Some(tools(&["read_file"]))
        );
        assert_eq!(
            effective_allowed_tools("read-only", Some(&tools(&["write_file"]))),
            Some(Vec::new())
        );
        assert_eq!(effective_allowed_tools("read-only", None), None);
        assert_eq!(
            effective_allowed_tools(
                "approval-required",
                Some(&tools(&["read_file", "run_command", "git_commit", "write_file"])),
            ),
            Some(tools(&["read_file", "write_file"]))
        );
        assert_eq!(
            effective_allowed_tools("workspace-modify", Some(&tools(&["write_file"]))),
            Some(tools(&["write_file"]))
        );
        assert_eq!(
            effective_allowed_tools("terminal", Some(&tools(&["create_terminal"]))),
            Some(tools(&["create_terminal"]))
        );
        assert_eq!(
            effective_allowed_tools("bogus", Some(&tools(&["read_file"]))),
            Some(Vec::new())
        );
    }

    #[test]
    fn materialized_allowed_tools_restricts_unlisted_profiled_threads() {
        let read_only = materialized_allowed_tools("read-only", None)
            .expect("read-only materializes a list");
        assert_eq!(read_only.len(), 187);
        assert!(read_only.contains(&"read_file".to_string()));
        assert!(read_only.contains(&"test_coverage_report".to_string()));
        assert!(read_only.contains(&"device_list".to_string()));
        assert!(read_only.contains(&"system_asset_read".to_string()));
        assert!(read_only.contains(&"system_asset_list".to_string()));
        assert!(read_only.contains(&"system_asset_get_metadata".to_string()));
        assert!(read_only.contains(&"system_asset_search_related".to_string()));
        assert!(!read_only.contains(&"write_file".to_string()));
        assert!(!read_only.contains(&"run_command".to_string()));
        assert!(!read_only.contains(&"git_branch_manager".to_string()));
        assert!(!read_only.contains(&"use_mcp".to_string()));
        let approval = materialized_allowed_tools("approval-required", None)
            .expect("approval-required materializes a list");
        assert_eq!(approval.len(), 251);
        assert!(approval.contains(&"read_file".to_string()));
        assert!(approval.contains(&"write_file".to_string()));
        assert!(approval.contains(&"read_terminal".to_string()));
        assert!(approval.contains(&"use_mcp".to_string()));
        assert!(approval.contains(&"system_asset_read".to_string()));
        assert!(approval.contains(&"system_asset_list".to_string()));
        assert!(approval.contains(&"system_asset_get_metadata".to_string()));
        assert!(approval.contains(&"system_asset_search_related".to_string()));
        assert!(!approval.contains(&"run_command".to_string()));
        assert!(!approval.contains(&"device_list".to_string()));
        assert!(!approval.contains(&"git_branch_manager".to_string()));
        assert_eq!(materialized_allowed_tools("workspace-modify", None), None);
        assert_eq!(materialized_allowed_tools("terminal", None), None);
        assert_eq!(
            materialized_allowed_tools("bogus", None),
            Some(Vec::new())
        );
        let tools = |names: &[&str]| {
            names
                .iter()
                .map(|name| name.to_string())
                .collect::<Vec<_>>()
        };
        assert_eq!(
            materialized_allowed_tools("read-only", Some(&tools(&["read_file", "write_file"]))),
            Some(tools(&["read_file"]))
        );
    }

    #[test]
    fn registry_partitions_by_profile() {
        for profile in ["read-only", "approval-required"] {
            let denied = TOOL_REGISTRY
                .iter()
                .filter(|tool| tool_denied_by_profile(profile, tool))
                .count();
            let allowed = TOOL_REGISTRY
                .iter()
                .filter(|tool| !tool_denied_by_profile(profile, tool))
                .count();
            assert_eq!(denied + allowed, 337);
        }
        assert_eq!(
            TOOL_REGISTRY
                .iter()
                .filter(|tool| tool_denied_by_profile("read-only", tool))
                .count(),
            150
        );
        assert_eq!(
            TOOL_REGISTRY
                .iter()
                .filter(|tool| tool_denied_by_profile("approval-required", tool))
                .count(),
            86
        );
    }

    #[test]
    fn terminal_profile_imposes_no_ceiling_beyond_allowed_tools() {
        for tool in TOOL_REGISTRY {
            assert!(!tool_denied_by_profile("terminal", tool));
            assert!(!tool_denied_by_profile("workspace-modify", tool));
        }
        let materialized = materialized_allowed_tools("terminal", None);
        assert_eq!(materialized, None);
    }

    #[test]
    fn disputed_read_only_names_follow_handler_evidence() {
        for tool in [
            "icon_generator_tool",
            "project_capabilities",
            "project_info_plist",
            "use_app",
            "use_mcp",
            "use_system",
            "git_branch_manager",
        ] {
            assert!(
                tool_denied_by_profile("read-only", tool),
                "{tool} must be denied for read-only"
            );
        }
        for tool in ["test_coverage_report", "test_coverage_reporter"] {
            assert!(
                !tool_denied_by_profile("read-only", tool),
                "{tool} must be allowed for read-only"
            );
        }
    }

    #[test]
    fn disputed_approval_required_names_follow_handler_evidence() {
        for tool in [
            "binary_size_report",
            "code_signing_diagnose",
            "device_list",
            "disk_space_analyzer",
            "gzip_compress_file",
            "gzip_decompress_file",
            "icon_generator_tool",
            "image_convert_format",
            "image_extract_metadata",
            "image_generate_thumbnail",
            "image_get_dimensions",
            "mach_o_binary_analyzer",
            "package_dependency_audit",
            "package_manifest_validate",
            "preflight_checks",
            "process_monitor_tool",
            "project_build_settings",
            "project_scheme_list",
            "project_signing",
            "project_target_list",
            "provisioning_check",
            "provisioning_profile_reader",
            "reverse_analyze",
            "signing_certificate_inspector",
            "simulator_list",
            "spm_dependency_tree",
            "svg_to_png",
            "swift_ast_inspector",
            "swift_format_lint",
            "tar_archive_create",
            "tar_archive_extract",
            "test_coverage_report",
            "test_coverage_reporter",
            "unzip_file",
            "use_system",
            "xcode_build_settings_inspector",
            "xcode_device_destination_finder",
            "xcode_scheme_manager",
            "xcode_toolchain_info",
            "xcresult_parser",
            "zip_file",
            "dir_delete",
            "file_delete",
            "git_branch_manager",
            "manage_memory",
            "project_snapshot",
        ] {
            assert!(
                tool_denied_by_profile("approval-required", tool),
                "{tool} must be denied for approval-required"
            );
        }
        for tool in [
            "use_mcp",
            "read_terminal",
            "project_capabilities",
            "project_info_plist",
        ] {
            assert!(
                !tool_denied_by_profile("approval-required", tool),
                "{tool} must be allowed for approval-required"
            );
        }
    }

    #[test]
    fn approval_required_is_not_a_subset_of_read_only_by_design() {
        for tool in [
            "binary_size_report",
            "code_signing_diagnose",
            "device_list",
            "disk_space_analyzer",
            "image_extract_metadata",
            "image_get_dimensions",
            "mach_o_binary_analyzer",
            "package_dependency_audit",
            "package_manifest_validate",
            "process_monitor_tool",
            "project_build_settings",
            "project_scheme_list",
            "project_signing",
            "project_target_list",
            "provisioning_check",
            "provisioning_profile_reader",
            "reverse_analyze",
            "signing_certificate_inspector",
            "simulator_list",
            "spm_dependency_tree",
            "swift_ast_inspector",
            "test_coverage_report",
            "test_coverage_reporter",
            "xcode_build_settings_inspector",
            "xcode_device_destination_finder",
            "xcode_scheme_manager",
            "xcode_toolchain_info",
            "xcresult_parser",
        ] {
            assert!(
                !tool_denied_by_profile("read-only", tool),
                "{tool} is a pure read and stays allowed for read-only"
            );
            assert!(
                tool_denied_by_profile("approval-required", tool),
                "{tool} executes through the terminal and stays denied for approval-required"
            );
        }
        let non_subset = TOOL_REGISTRY
            .iter()
            .filter(|tool| {
                tool_denied_by_profile("approval-required", tool)
                    && !tool_denied_by_profile("read-only", tool)
            })
            .count();
        assert_eq!(non_subset, 28);
    }
}
