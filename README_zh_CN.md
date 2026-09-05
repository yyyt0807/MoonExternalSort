# MoonExternalSort

MoonExternalSort 是使用 MoonBit 实现的稳定、有界内存外部排序与多路归并引擎。它把大于可用内存的 UTF-8 文本、TSV 或 JSONL 记录流拆成有序 Run，在文件句柄预算内执行多轮 k 路归并，并通过原子 Job Manifest 支持从最近一次已提交阶段恢复。

## 核心保证

- 相同 Sort Key 的记录始终保持原输入顺序，包括降序模式；
- Run Builder 的记录常驻估算不会超过 `memory_budget_bytes`；
- 行帧在读取阶段强制执行 `max_record_bytes`，不会先无界读取再检查；
- 每个 Merge Group 最多打开 `max_open_runs` 个输入 Run；
- 只有完整写入的 Run 才会进入原子提交的 Job Manifest；
- Published Output 先写临时文件，再通过重命名一次性可见；
- 空输入、空记录、CRLF、重复键、负整数键和多轮归并都有测试。

`memory_budget_bytes` 约束生成 Run 时保留的记录。归并阶段的已解码记录头由
`max_open_runs` 单独约束；文本键的保守记录数据上界为
`max_open_runs * (2 * max_record_bytes + 32)`。两者都不是操作系统级 RSS
上限，MoonBit 运行时、文件系统、堆容器和编码器仍会使用额外内存。

## 快速验证

```sh
moon update
moon check --target all --deny-warn
moon test --target all --deny-warn
moon run examples/library-demo
```

排序 TSV 第一列，按有符号整数升序：

```sh
moon run --target native cmd/moon-external-sort -- sort \
  examples/data/records.tsv _build/sorted.tsv \
  --field-index 0 --numeric \
  --memory-bytes 512 --max-record-bytes 128
```

按 JSONL 顶层 `priority` 字段降序排序：

```sh
moon run --target native cmd/moon-external-sort -- sort \
  examples/data/events.jsonl _build/events.sorted.jsonl \
  --json-field priority --numeric --descending --force
```

命令成功后会输出 JSON 报告。默认恢复目录是 `OUTPUT.moon-sort-work`，恢复命令为：

```sh
moon run --target native cmd/moon-external-sort -- resume \
  OUTPUT.moon-sort-work/manifest.json
```

## 库接口

便携核心提供：

- `SortConfig`、`SortRecord`、`SortValue` 和 `KeySelector`；
- `RunBuilder`：按预算生成稳定有序 Run；
- `merge_sorted_runs`：用于内存存储和参考验证的堆式 k 路归并；
- `plan_merge_pass`、`merge_pass_count`：受限 fan-in 规划；
- `LineFramer`：按字节限制的 UTF-8 行边界构造器；
- `JobManifest` 及其稳定 JSON 编解码；
- `adapter/native`：文件 Run、原子清单、恢复和最终发布。

完整说明参见 [API](docs/API.md)、[架构](docs/ARCHITECTURE.md)、[测试](docs/TESTING.md)、[安全边界](docs/SECURITY.md) 和 [生态对比](docs/ECOSYSTEM_COMPARISON.md)。

## 明确不做

- 不做数据库、DataFrame、SQL 或分布式流处理；
- 不做任意用户脚本比较器；
- 不承诺操作系统级硬内存隔离；
- 不把恢复清单当作抵御恶意篡改的安全格式；
- 不删除用户提供的工作目录，成功后保留 Manifest 作为证据。

本项目为原创 MoonBit 实现，采用 Apache-2.0 许可证。
