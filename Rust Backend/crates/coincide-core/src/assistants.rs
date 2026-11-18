use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value, json};
use std::collections::HashSet;
use uuid::Uuid;

pub const NAME_LIMIT: usize = 1024;
pub const DESCRIPTION_LIMIT: usize = 4096;
pub const ICON_LIMIT: usize = 128;
pub const SYSTEM_PROMPT_LIMIT: usize = 1_048_576;
pub const INTENDED_TASK_LIMIT: usize = 512;
pub const INTENDED_TASKS_LIMIT: usize = 32;
pub const OUTPUT_FORMAT_LIMIT: usize = 4096;
pub const TOOL_NAME_LIMIT: usize = 256;
pub const MODEL_LIMIT: usize = 256;
pub const INPUT_REQUIREMENT_LIMIT: usize = 512;
pub const INPUT_REQUIREMENTS_LIMIT: usize = 16;

pub const CATEGORIES: &[&str] = &[
    "code-maintenance",
    "code-review-security",
    "building-fixing",
    "repository-intelligence",
    "git-workflow-automation",
    "specialized-productivity",
];

pub const PERMISSION_PROFILES: &[&str] = &[
    "read-only",
    "workspace-modify",
    "terminal",
    "approval-required",
];

pub const SOURCES: &[&str] = &["custom", "override"];

fn default_permission_profile() -> String {
    "read-only".to_string()
}

fn default_assistant_version() -> i64 {
    1
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Assistant {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub icon: String,
    pub category: String,
    pub system_prompt: String,
    #[serde(default)]
    pub intended_tasks: Vec<String>,
    #[serde(default)]
    pub expected_output_format: String,
    #[serde(default)]
    pub allowed_tools: Option<Vec<String>>,
    #[serde(default)]
    pub provider: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default = "default_permission_profile")]
    pub permission_profile: String,
    #[serde(default)]
    pub input_requirements: Option<Vec<String>>,
    #[serde(default = "default_assistant_version")]
    pub version: i64,
    pub source: String,
    #[serde(default)]
    pub is_favorite: bool,
    #[serde(default)]
    pub last_used_at: Option<i64>,
    #[serde(default)]
    pub created_at: i64,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl Assistant {
    pub fn validate(&self) -> Result<()> {
        Uuid::parse_str(&self.id).context("Invalid assistant ID")?;
        ensure!(
            !self.name.trim().is_empty()
                && self.name.chars().count() <= NAME_LIMIT
                && !self.name.chars().any(char::is_control),
            "Assistant name must contain 1-1024 characters without control characters"
        );
        ensure!(
            self.description.chars().count() <= DESCRIPTION_LIMIT
                && !self.description.contains('\0'),
            "Assistant description must contain at most 4096 characters and no NUL"
        );
        ensure!(
            self.icon.chars().count() <= ICON_LIMIT
                && !self.icon.chars().any(char::is_control),
            "Assistant icon must contain at most 128 characters without control characters"
        );
        ensure!(
            CATEGORIES.contains(&self.category.as_str()),
            "Unknown assistant category"
        );
        ensure!(
            !self.system_prompt.trim().is_empty()
                && self.system_prompt.len() <= SYSTEM_PROMPT_LIMIT
                && !self.system_prompt.contains('\0'),
            "Assistant instructions must be non-empty, at most 1 MiB, and contain no NUL"
        );
        ensure!(
            self.intended_tasks.len() <= INTENDED_TASKS_LIMIT,
            "An assistant can list at most 32 intended tasks"
        );
        for task in &self.intended_tasks {
            ensure!(
                task.chars().count() <= INTENDED_TASK_LIMIT && !task.contains('\0'),
                "Each intended task must contain at most 512 characters and no NUL"
            );
        }
        ensure!(
            self.expected_output_format.chars().count() <= OUTPUT_FORMAT_LIMIT
                && !self.expected_output_format.contains('\0'),
            "Assistant output format must contain at most 4096 characters and no NUL"
        );
        if let Some(tools) = &self.allowed_tools {
            let mut seen = HashSet::new();
            for tool in tools {
                ensure!(
                    !tool.trim().is_empty()
                        && tool.chars().count() <= TOOL_NAME_LIMIT
                        && !tool.chars().any(char::is_control),
                    "Assistant tool names must be non-empty text of at most 256 characters"
                );
                ensure!(seen.insert(tool), "Duplicate assistant tool name");
            }
        }
        if let Some(provider) = &self.provider {
            crate::agent::Provider::from_name(provider)
                .with_context(|| format!("Unknown assistant provider: {provider}"))?;
        }
        if let Some(model) = &self.model {
            ensure!(
                !model.trim().is_empty() && model.chars().count() <= MODEL_LIMIT,
                "Assistant model must contain at most 256 characters"
            );
        }
        ensure!(
            PERMISSION_PROFILES.contains(&self.permission_profile.as_str()),
            "Unknown assistant permission profile"
        );
        if let Some(requirements) = &self.input_requirements {
            ensure!(
                requirements.len() <= INPUT_REQUIREMENTS_LIMIT,
                "An assistant can list at most 16 input requirements"
            );
            for requirement in requirements {
                ensure!(
                    requirement.chars().count() <= INPUT_REQUIREMENT_LIMIT
                        && !requirement.contains('\0'),
                    "Each input requirement must contain at most 512 characters and no NUL"
                );
            }
        }
        ensure!(
            self.version >= 1,
            "Assistant version must be at least 1"
        );
        ensure!(
            SOURCES.contains(&self.source.as_str()),
            "Unknown assistant source"
        );
        ensure!(
            self.last_used_at.is_none_or(|at| at >= 0),
            "Assistant last-used time must be an epoch timestamp"
        );
        ensure!(
            self.created_at >= 0 && self.updated_at >= 0,
            "Assistant timestamps must be epoch timestamps"
        );
        Ok(())
    }
}

pub fn validate_assistant(value: &Value) -> Result<Assistant> {
    let assistant: Assistant =
        serde_json::from_value(value.clone()).context("Assistant record is invalid")?;
    assistant.validate()?;
    Ok(assistant)
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AssistantsDocument {
    pub version: u32,
    pub assistants: Vec<Assistant>,
    #[serde(flatten)]
    pub extra: Map<String, Value>,
}

impl AssistantsDocument {
    pub fn validate(&self) -> Result<Vec<u8>> {
        ensure!(
            self.version == 1,
            "Unsupported assistants document version"
        );
        ensure!(
            self.assistants.len() <= crate::organization::RECORD_LIMIT,
            "Too many assistants"
        );
        let mut seen = HashSet::new();
        for assistant in &self.assistants {
            assistant.validate()?;
            ensure!(
                seen.insert(Uuid::parse_str(&assistant.id)?),
                "Duplicate assistant ID"
            );
        }
        let bytes = serde_json::to_vec(self)?;
        ensure!(
            bytes.len() <= crate::organization::DOCUMENT_LIMIT,
            "Assistants document exceeds size limit"
        );
        Ok(bytes)
    }
}

pub fn empty_document() -> Value {
    json!({"version": 1, "assistants": []})
}
