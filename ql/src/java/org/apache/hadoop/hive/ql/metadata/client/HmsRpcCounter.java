/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package org.apache.hadoop.hive.ql.metadata.client;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Proxy;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.LongAdder;

import org.apache.hadoop.hive.metastore.IMetaStoreClient;
import org.apache.hadoop.hive.ql.session.SessionState;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * MEASUREMENT ONLY (HIVE-30249 baseline), not for commit: counts the IMetaStoreClient calls that reach
 * the Thrift client while a query-level HMS cache is active (i.e. during compilation).
 */
public final class HmsRpcCounter {
  private static final Logger LOG = LoggerFactory.getLogger(HmsRpcCounter.class);
  private static final Map<String, LongAdder> COUNTS = new ConcurrentHashMap<>();

  private HmsRpcCounter() {
  }

  public static IMetaStoreClient wrap(IMetaStoreClient client) {
    return (IMetaStoreClient) Proxy.newProxyInstance(HmsRpcCounter.class.getClassLoader(),
        new Class<?>[] { IMetaStoreClient.class }, (proxy, method, args) -> {
          if (isCompiling()) {
            COUNTS.computeIfAbsent(method.getName(), k -> new LongAdder()).increment();
          }
          try {
            return method.invoke(client, args);
          } catch (InvocationTargetException e) {
            throw e.getCause();
          }
        });
  }

  private static boolean isCompiling() {
    SessionState ss = SessionState.get();
    if (ss == null) {
      return false;
    }
    String queryId = MetaStoreClientCacheUtils.getQueryId();
    return queryId != null && ss.getQueryCache(queryId) != null;
  }

  public static void reset() {
    COUNTS.clear();
  }

  public static void logAndReset(String queryId, double compileSeconds) {
    Map<String, Long> snapshot = new TreeMap<>();
    long total = 0;
    for (Map.Entry<String, LongAdder> e : COUNTS.entrySet()) {
      long v = e.getValue().sum();
      snapshot.put(e.getKey(), v);
      total += v;
    }
    COUNTS.clear();
    LOG.info("HMS-RPC queryId={} compileMs={} total={} {}", queryId, Math.round(compileSeconds * 1000), total,
        snapshot);
  }
}
