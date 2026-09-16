# Mermaid Diagram Examples

## Flowchart

```mermaid
graph LR
    A[Start] --> B{Decision}
    B -->|Yes| C[Action 1]
    B -->|No| D[Action 2]
    C --> E[End]
    D --> E
```

## Sequence Diagram

```mermaid
sequenceDiagram
    participant U as User
    participant S as Server
    participant D as Database
    
    U->>S: HTTP Request
    S->>D: Query
    D-->>S: Results
    S-->>U: JSON Response
```

## Entity Relationship Diagram

```mermaid
erDiagram
    USER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "ordered in"
```

## State Diagram

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing : start
    Processing --> Complete : success
    Processing --> Error : failure
    Complete --> [*]
    Error --> Idle : retry
```

## Class Diagram

```mermaid
classDiagram
    class User {
        +String name
        +String email
        +login()
        +logout()
    }
    class Order {
        +int id
        +Date created
        +process()
    }
    User "1" --> "*" Order : places
```

## Gantt Chart

```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    section Phase 1
    Research    :a1, 2024-01-01, 30d
    Design      :a2, after a1, 20d
    section Phase 2
    Development :a3, after a2, 60d
    Testing     :a4, after a3, 30d
```

## Pie Chart

```mermaid
pie title Browser Market Share
    "Chrome" : 65
    "Safari" : 19
    "Firefox" : 10
    "Other" : 6
```

## Markdown Transformation Example

### Input (template.md)

~~~markdown
# Architecture Overview

```mermaid
graph TD
    A[Frontend] --> B[API Gateway]
    B --> C[Service A]
    B --> D[Service B]
    C --> E[(Database)]
    D --> E
```

# Request Flow

```mermaid
sequenceDiagram
    User->>Frontend: Click button
    Frontend->>API: POST /action
    API->>Service: Process
    Service-->>API: Result
    API-->>Frontend: 200 OK
    Frontend-->>User: Show success
```
~~~

### Command

```bash
mmdc -i template.md -o docs/architecture.md -a docs/images/ -t default -b white
```

### Output (docs/architecture.md)

```markdown
# Architecture Overview

![diagram](./images/architecture-1.png)

# Request Flow

![diagram](./images/architecture-2.png)
```
