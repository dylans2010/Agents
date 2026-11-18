use super::*;
use community_links::{Group, LINKS, Link};

/// "Coincide 0.1.0 (Rust desktop, macos aarch64), macOS 26.1 (25B78)", for bug
/// reports.
fn version_report() -> String {
    match community_links::system_version() {
        Some(system) => format!("Coincide {}, {system}", community_links::app_version()),
        None => format!("Coincide {}", community_links::app_version()),
    }
}
fn icon() -> Arc<Image> {
    static ICON: std::sync::OnceLock<Arc<Image>> = std::sync::OnceLock::new();
    ICON.get_or_init(|| {
        Arc::new(Image::from_bytes(
            ImageFormat::Png,
            include_bytes!("../assets/app-icon.png").to_vec(),
        ))
    })
    .clone()
}
const T3_CODE_LICENSE: &str = "MIT License

Copyright (c) 2026 T3 Tools Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.";

impl Coincide {
    fn about_link(
        &self,
        id: &'static str,
        icon: gpui_kit::assets::IconName,
        tint: u32,
        title: &'static str,
        detail: &'static str,
        url: String,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let tooltip = url.clone();
        Button::new(SharedString::from(format!("about-link-{id}")))
            .ghost()
            .w_full()
            .h_auto()
            .accessibility_label(title)
            .tooltip(tooltip)
            .child(
                div()
                    .w_full()
                    .flex()
                    .items_center()
                    .gap(px(10.))
                    .py_1()
                    .child(
                        div()
                            .w(px(24.))
                            .h(px(24.))
                            .flex_shrink_0()
                            .rounded(px(6.))
                            .bg(rgb(tint))
                            .text_color(rgb(0xffffff))
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(Icon::new(icon).xsmall()),
                    )
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .child(title)
                            .child(
                                div()
                                    .text_xs()
                                    .text_color(self.color(0x98a6ba).opacity(0.7))
                                    .child(detail),
                            ),
                    )
                    .child(Icon::new(gpui_kit::assets::IconName::ExternalLink).xsmall()),
            )
            .on_click(cx.listener(move |_, _, _, cx| cx.open_url(&url)))
            .into_any_element()
    }

    fn about_section(&self, title: &'static str, rows: Vec<AnyElement>) -> Div {
        div()
            .flex()
            .flex_col()
            .gap_1()
            .child(div().mt_2().text_lg().child(title))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .rounded_md()
                    .border_1()
                    .border_color(self.color(0x29303d))
                    .bg(self.color(0x111722))
                    .p_1()
                    .children(rows),
            )
    }

    pub(super) fn about_settings(&self, cx: &mut Context<Self>) -> AnyElement {
        let report = version_report();
        let mut content = div().flex().flex_col().gap_3()
            .child(div().flex().flex_col().items_center().gap_2().p_4()
                .child(img(icon()).w(px(112.)).h(px(112.)))
                .child(div().text_xl().font_weight(FontWeight::SEMIBOLD).child("Coincide"))
                .child(div().text_color(self.color(0x98a6ba).opacity(0.8)).child(format!("Version {}", community_links::app_version())))
                .child("One window for the coding agents you already use. Switch agents mid-thread while each keeps its own session.")
                .child(Button::new("about-copy-version").label("Copy Version Info").on_click(cx.listener(move |_,_,_,cx| {
                    cx.write_to_clipboard(ClipboardItem::new_string(report.clone()));
                }))));
        // App Updates stays unavailable unless the trusted launcher configured a
        // preview channel; mounting it never checks a feed by itself.
        content = content.child(self.updater_settings.clone());
        for group in Group::ALL {
            let rows = LINKS
                .iter()
                .filter(|link| link.group == group)
                .map(|link: &Link| {
                    self.about_link(
                        link.id,
                        link.icon,
                        link.tint,
                        link.title,
                        link.detail,
                        link.url(),
                        cx,
                    )
                })
                .collect();
            content = content.child(self.about_section(group.title(), rows));
        }
        let license_open = self.general_settings.t3_license_open;
        let acp_license_open = self.general_settings.acp_registry_license_open;
        let acknowledgements = vec![
            div().p_2().child("Coincide ports the design and behavior of T3 Code, the open-source agent app by T3 Tools Inc., used under the MIT License.").into_any_element(),
            self.about_link("t3code", gpui_kit::assets::IconName::GitBranch, 0x5856d6, "T3 Code", "github.com/pingdotgg/t3code", "https://github.com/pingdotgg/t3code".into(), cx),
            Button::new("about-t3-license")
                .ghost()
                .w_full()
                .child(div().w_full().flex().items_center().gap_2()
                    .child(Icon::new(if license_open { gpui_kit::assets::IconName::ChevronDown } else { gpui_kit::assets::IconName::ChevronRight }).xsmall())
                    .child("T3 Code License"))
                .on_click(cx.listener(|this, _, _, cx| {
                    this.general_settings.t3_license_open = !this.general_settings.t3_license_open;
                    cx.notify();
                }))
                .into_any_element(),
            div().when(license_open, |view| view.p_2().text_xs().font_family("monospace").text_color(self.color(0x98a6ba).opacity(0.8)).child(T3_CODE_LICENSE)).into_any_element(),
            div().p_2().child("The offline agent catalog includes metadata from the ACP Registry, under the Apache License 2.0.").into_any_element(),
            Button::new("about-acp-registry-license")
                .ghost().w_full()
                .child(div().w_full().flex().items_center().gap_2()
                    .child(Icon::new(if acp_license_open { gpui_kit::assets::IconName::ChevronDown } else { gpui_kit::assets::IconName::ChevronRight }).xsmall())
                    .child("ACP Registry License"))
                .on_click(cx.listener(|this, _, _, cx| {
                    this.general_settings.acp_registry_license_open = !this.general_settings.acp_registry_license_open;
                    cx.notify();
                })).into_any_element(),
            div().when(acp_license_open, |view| view.p_2().text_xs().font_family("monospace")
                .text_color(self.color(0x98a6ba).opacity(0.8))
                .child(include_str!("../../coincide-core/third_party/acp-registry/LICENSE"))).into_any_element(),
            div().p_2().child("The Rust desktop interface uses GPUI Kit, GPUI and GPUI WebView under the Apache-2.0 License.").into_any_element(),
            self.about_link("gpui-kit", gpui_kit::assets::IconName::Boxes, 0x8e8e93, "GPUI Kit", "crates.io/crates/gpui-kit", "https://crates.io/crates/gpui-kit".into(), cx),
            self.about_link("notices", gpui_kit::assets::IconName::FileText, 0x8e8e93, "License and third-party notices", "THIRD_PARTY_NOTICES.md", "https://github.com/dylans2010/Agents/blob/main/THIRD_PARTY_NOTICES.md".into(), cx),
        ];
        content
            .child(self.about_section("Acknowledgements", acknowledgements))
            .child(
                div()
                    .flex()
                    .justify_center()
                    .text_sm()
                    .text_color(self.color(0x98a6ba).opacity(0.8))
                    .child("Copyright © 2026 Apoorv Darshan"),
            )
            .into_any_element()
    }
}
