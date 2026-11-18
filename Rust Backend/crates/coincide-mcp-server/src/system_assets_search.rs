use anyhow::Result;
use std::collections::BTreeMap;
use std::path::Path;

pub struct SystemAssetSearchResult {
    pub document_id: String,
    pub file_name: String,
    pub title: String,
    pub section_heading: String,
    pub heading_path: Vec<String>,
    pub text: String,
    pub score: i64,
    pub reason: String,
}

pub struct SystemAssetSearchOutcome {
    pub document_count: usize,
    pub results: Vec<SystemAssetSearchResult>,
}

#[allow(dead_code)]
struct Section {
    heading: String,
    level: usize,
    heading_path: Vec<String>,
    body: String,
}

struct Document {
    id: String,
    file_name: String,
    title: String,
    sections: Vec<Section>,
    raw_text: String,
}

pub fn normalize(text: &str) -> String {
    let folded: String = text
        .chars()
        .flat_map(|c| c.to_lowercase())
        .flat_map(fold_char)
        .collect();
    folded
        .split_whitespace()
        .collect::<Vec<&str>>()
        .join(" ")
}

fn fold_char(c: char) -> Vec<char> {
    if ('\u{0300}'..='\u{036f}').contains(&c) {
        return Vec::new();
    }
    match c {
        'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' | 'ā' | 'ă' | 'ą' | 'ǎ' | 'ȁ' | 'ȃ' => vec!['a'],
        'ç' | 'ć' | 'ĉ' | 'ċ' | 'č' => vec!['c'],
        'ď' | 'đ' => vec!['d'],
        'è' | 'é' | 'ê' | 'ë' | 'ē' | 'ĕ' | 'ė' | 'ę' | 'ě' | 'ȅ' | 'ȇ' => vec!['e'],
        'ĝ' | 'ğ' | 'ġ' | 'ģ' => vec!['g'],
        'ĥ' | 'ħ' => vec!['h'],
        'ì' | 'í' | 'î' | 'ï' | 'ĩ' | 'ī' | 'ĭ' | 'į' | 'ı' => vec!['i'],
        'ĵ' => vec!['j'],
        'ķ' | 'ĸ' => vec!['k'],
        'ĺ' | 'ļ' | 'ľ' | 'ŀ' | 'ł' => vec!['l'],
        'ñ' | 'ń' | 'ņ' | 'ň' | 'ŉ' | 'ŋ' => vec!['n'],
        'ò' | 'ó' | 'ô' | 'õ' | 'ö' | 'ø' | 'ō' | 'ŏ' | 'ő' | 'ȍ' | 'ȏ' => vec!['o'],
        'ŕ' | 'ŗ' | 'ř' => vec!['r'],
        'ś' | 'ŝ' | 'ş' | 'š' | 'ș' => vec!['s'],
        'ţ' | 'ť' | 'ŧ' | 'ț' => vec!['t'],
        'ù' | 'ú' | 'û' | 'ü' | 'ũ' | 'ū' | 'ŭ' | 'ů' | 'ű' | 'ų' | 'ȕ' | 'ȗ' => vec!['u'],
        'ŵ' => vec!['w'],
        'ý' | 'ÿ' | 'ŷ' => vec!['y'],
        'ź' | 'ż' | 'ž' => vec!['z'],
        'æ' => vec!['a', 'e'],
        'œ' => vec!['o', 'e'],
        'ß' => vec!['s', 's'],
        'ĳ' => vec!['i', 'j'],
        _ => vec![c],
    }
}

pub fn tokenize(normalized: &str) -> Vec<String> {
    normalized
        .split(|c: char| !c.is_alphanumeric())
        .filter(|part| !part.is_empty())
        .map(str::to_owned)
        .collect()
}

fn parse_title(lines: &[&str], fallback: &str) -> String {
    for line in lines {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("# ") {
            let title = rest.trim();
            if !title.is_empty() {
                return title.to_owned();
            }
        }
    }
    fallback.to_owned()
}

fn parse_heading(line: &str) -> Option<(usize, String)> {
    let trimmed = line.trim();
    let hashes = trimmed.chars().take_while(|c| *c == '#').count();
    if hashes < 1 || hashes > 6 {
        return None;
    }
    let rest = &trimmed[hashes..];
    let after = rest.strip_prefix(' ')?;
    let text = after.trim();
    if text.is_empty() {
        return None;
    }
    Some((hashes, text.to_owned()))
}

fn flush_section(
    sections: &mut Vec<Section>,
    heading: &str,
    level: usize,
    heading_path: &[String],
    body_lines: &[String],
) {
    let body = body_lines.join("\n");
    let body = body.trim();
    if !heading.is_empty() || !body.is_empty() {
        sections.push(Section {
            heading: heading.to_owned(),
            level,
            heading_path: heading_path.to_owned(),
            body: body.to_owned(),
        });
    }
}

fn parse_sections(lines: &[&str], title: &str) -> Vec<Section> {
    let mut sections: Vec<Section> = Vec::new();
    let mut heading_stack: Vec<(usize, String)> = Vec::new();
    let mut current_heading = String::new();
    let mut current_level: usize = 0;
    let mut current_body: Vec<String> = Vec::new();
    let mut saw_heading = false;
    for line in lines {
        let trimmed = line.trim();
        if let Some((level, text)) = parse_heading(trimmed) {
            let heading_path: Vec<String> =
                heading_stack.iter().map(|entry| entry.1.clone()).collect();
            if saw_heading {
                flush_section(
                    &mut sections,
                    &current_heading,
                    current_level,
                    &heading_path,
                    &current_body,
                );
            } else if !current_body.join("\n").trim().is_empty() {
                flush_section(&mut sections, &current_heading, current_level, &[], &current_body);
            }
            saw_heading = true;
            while let Some(last) = heading_stack.last() {
                if last.0 >= level {
                    heading_stack.pop();
                } else {
                    break;
                }
            }
            heading_stack.push((level, text.clone()));
            current_heading = text;
            current_level = level;
            current_body = Vec::new();
        } else {
            if trimmed.starts_with("<!-- system-index-") {
                continue;
            }
            current_body.push((*line).to_owned());
        }
    }
    if saw_heading {
        let heading_path: Vec<String> =
            heading_stack.iter().map(|entry| entry.1.clone()).collect();
        flush_section(
            &mut sections,
            &current_heading,
            current_level,
            &heading_path,
            &current_body,
        );
    } else {
        let body = current_body.join("\n");
        let body = body.trim();
        if !body.is_empty() {
            sections.push(Section {
                heading: title.to_owned(),
                level: 1,
                heading_path: vec![title.to_owned()],
                body: body.to_owned(),
            });
        }
    }
    sections
}

fn parse_document(file_name: &str, raw_text: &str) -> Option<Document> {
    if raw_text.trim().is_empty() {
        return None;
    }
    let id = file_name
        .strip_suffix(".md")
        .unwrap_or(file_name)
        .to_owned();
    let lines: Vec<&str> = raw_text.split('\n').collect();
    let title = parse_title(&lines, &id);
    let sections = parse_sections(&lines, &title);
    Some(Document {
        id,
        file_name: file_name.to_owned(),
        title,
        sections,
        raw_text: raw_text.to_owned(),
    })
}

fn display_text(section: &Section) -> String {
    if section.heading.is_empty() {
        section.body.clone()
    } else {
        section.heading.clone() + "\n\n" + &section.body
    }
}

pub fn search(dir: &Path, query: &str, limit: usize) -> Result<SystemAssetSearchOutcome> {
    let names = crate::assets::list_asset_names(dir)?;
    let document_count = names.len();
    let normalized_query = normalize(query);
    if normalized_query.is_empty() {
        return Ok(SystemAssetSearchOutcome {
            document_count,
            results: Vec::new(),
        });
    }
    let tokens = tokenize(&normalized_query);
    let mut documents: Vec<Document> = Vec::new();
    for file_name in &names {
        let Ok(content) = crate::assets::read_asset_text(dir, file_name) else {
            continue;
        };
        if let Some(document) = parse_document(file_name, &content) {
            documents.push(document);
        }
    }
    let mut best_by_key: BTreeMap<String, SystemAssetSearchResult> = BTreeMap::new();
    for document in &documents {
        let normalized_title = normalize(&document.title);
        let normalized_file_name = normalize(&document.file_name);
        let normalized_id = normalize(&document.id);
        if normalized_query == normalized_file_name || normalized_query == normalized_id {
            let first = document.sections.first();
            let result = SystemAssetSearchResult {
                document_id: document.id.clone(),
                file_name: document.file_name.clone(),
                title: document.title.clone(),
                section_heading: first
                    .map(|section| section.heading.clone())
                    .unwrap_or_else(|| document.title.clone()),
                heading_path: first
                    .map(|section| section.heading_path.clone())
                    .unwrap_or_else(|| vec![document.title.clone()]),
                text: first
                    .map(display_text)
                    .unwrap_or_else(|| document.raw_text.clone()),
                score: 100,
                reason: "exactFilename".to_owned(),
            };
            best_by_key.insert(document.id.clone(), result);
            continue;
        }
        if normalized_query == normalized_title {
            let first = document.sections.first();
            let result = SystemAssetSearchResult {
                document_id: document.id.clone(),
                file_name: document.file_name.clone(),
                title: document.title.clone(),
                section_heading: first
                    .map(|section| section.heading.clone())
                    .unwrap_or_else(|| document.title.clone()),
                heading_path: first
                    .map(|section| section.heading_path.clone())
                    .unwrap_or_else(|| vec![document.title.clone()]),
                text: first
                    .map(display_text)
                    .unwrap_or_else(|| document.raw_text.clone()),
                score: 90,
                reason: "exactTitle".to_owned(),
            };
            best_by_key.insert(document.id.clone(), result);
            continue;
        }
        for section in &document.sections {
            let normalized_heading = normalize(&section.heading);
            let normalized_body = normalize(&section.body);
            let combined = normalized_heading.clone() + " " + &normalized_body;
            let (score, reason) =
                if !normalized_heading.is_empty() && normalized_heading == normalized_query {
                    (80, "exactHeading")
                } else if combined.contains(normalized_query.as_str()) {
                    let occurrences = combined.matches(normalized_query.as_str()).count();
                    (70 + std::cmp::min(10, occurrences as i64), "phrase")
                } else {
                    let mut token_score: i64 = 0;
                    for token in &tokens {
                        if normalized_title.contains(token.as_str()) {
                            token_score += 5;
                        }
                        if normalized_heading.contains(token.as_str()) {
                            token_score += 4;
                        }
                        if normalized_body.contains(token.as_str()) {
                            token_score += 1;
                        }
                    }
                    if token_score == 0 {
                        continue;
                    }
                    (std::cmp::min(69, token_score), "keyword")
                };
            let key = document.id.clone() + "|" + &section.heading;
            let result = SystemAssetSearchResult {
                document_id: document.id.clone(),
                file_name: document.file_name.clone(),
                title: document.title.clone(),
                section_heading: section.heading.clone(),
                heading_path: section.heading_path.clone(),
                text: display_text(section),
                score,
                reason: reason.to_owned(),
            };
            let keep_existing = best_by_key
                .get(&key)
                .is_some_and(|existing| existing.score >= score);
            if !keep_existing {
                best_by_key.insert(key, result);
            }
        }
    }
    let mut ranked: Vec<SystemAssetSearchResult> = best_by_key.into_values().collect();
    ranked.sort_by(|a, b| {
        b.score
            .cmp(&a.score)
            .then_with(|| a.file_name.cmp(&b.file_name))
            .then_with(|| a.section_heading.cmp(&b.section_heading))
    });
    ranked.truncate(limit);
    Ok(SystemAssetSearchOutcome {
        document_count,
        results: ranked,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_folds_case_diacritics_and_whitespace() {
        assert_eq!(normalize("  Café   MENU\nGuide "), "cafe menu guide");
        assert_eq!(normalize(""), "");
        assert_eq!(normalize("   "), "");
    }

    #[test]
    fn tokenize_splits_on_hyphens_and_punctuation() {
        assert_eq!(
            tokenize("getting-started guide"),
            vec!["getting".to_owned(), "started".to_owned(), "guide".to_owned()]
        );
        assert_eq!(tokenize(""), Vec::<String>::new());
    }

    #[test]
    fn parse_sections_tracks_heading_paths() {
        let lines: Vec<&str> = "# Alpha Guide\n\n## Getting Started\nBody text.\n"
            .split('\n')
            .collect();
        let sections = parse_sections(&lines, "Alpha Guide");
        assert_eq!(sections.len(), 2);
        assert_eq!(sections[0].heading, "Alpha Guide");
        assert_eq!(sections[0].heading_path, vec!["Alpha Guide".to_owned()]);
        assert_eq!(sections[0].body, "");
        assert_eq!(sections[1].heading, "Getting Started");
        assert_eq!(
            sections[1].heading_path,
            vec!["Alpha Guide".to_owned(), "Getting Started".to_owned()]
        );
        assert_eq!(sections[1].body, "Body text.");
    }
}
