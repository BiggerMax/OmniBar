//
//  AboutSettings.swift
//  OmniBar
//
//  关于页：品牌大图标（带光晕） + 版本胶囊 + GitHub 链接 + 版权
//

import SwiftUI

struct AboutSettings: View {
    private var version: String {
        let bundle = Bundle(for: AppDelegate.self)
        let v = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: DT.Space.xxl) {
            Spacer()
            // 品牌大图标 + 光晕
            ZStack {
                Circle()
                    .fill(DT.Color.accent.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .blur(radius: 20)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DT.Color.accent, DT.Color.accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: DT.Color.accent.opacity(0.4), radius: 16, x: 0, y: 8)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: DT.Space.xs) {
                Text("OmniBar")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(DT.Color.textPrimary)
                Text("Omniroute macOS Menu Bar Manager")
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            // 版本胶囊
            Text("VERSION \(version)".uppercased())
                .font(DT.Font.monoSmall)
                .foregroundStyle(DT.Color.textSecondary)
                .tracking(1.0)
                .padding(.horizontal, DT.Space.l)
                .padding(.vertical, DT.Space.xs)
                .background(Capsule().fill(DT.Color.surfaceElevated))
                .overlay(Capsule().strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5))

            // GitHub 链接
            Link(destination: URL(string: "https://github.com/BiggerMax/OmniBar")!) {
                HStack {
                    HStack(spacing: DT.Space.m) {
                        Circle()
                            .fill(DT.Color.accent)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle().fill(DT.Color.accent)
                                    .frame(width: 6, height: 6)
                                    .blur(radius: 2)
                            )
                        Text("GitHub 仓库")
                            .font(DT.Font.bodyMedium)
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .padding(.horizontal, DT.Space.xl)
                .padding(.vertical, DT.Space.l)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .fill(DT.Color.surfaceElevated.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .strokeBorder(DT.Color.strokeVariant, lineWidth: 0.5)
                )
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: 320)

            Spacer()
            Text("© 2024 OmniRoute Technologies. All rights reserved.")
                .font(DT.Font.monoTiny)
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, DT.Space.xxxl)
    }
}
